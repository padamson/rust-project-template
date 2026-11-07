#!/usr/bin/env bash
# The check and fix functions are called through run_item's arguments.
# shellcheck disable=SC2329
# Check, and with --apply set, the GitHub settings SETUP.md lists for this
# repo: the ones no file in the tree can carry. Run from anywhere in the
# checkout; the repo is the one `gh repo view` names.
#
#   ./scripts/github-settings.sh              # report, change nothing
#   ./scripts/github-settings.sh --apply      # set whatever is off
#   ./scripts/github-settings.sh --apply \
#       --app-client-id <id> --app-key <app>.private-key.pem
#                                             # also write the merge App's secrets
#
# One line per setting: `ok`, `set` (changed by this run), `DRIFT` (off,
# and --check or no input to fix it), `FAILED` (--apply tried and it did
# not take), `UNREAD` (gh could not read it), or `manual` (no API this
# script can use; do it on github.com). Exit 0 when nothing is DRIFT,
# FAILED or UNREAD, 1 otherwise, 2 on a usage error.
#
# Run it from a plain terminal. In a Claude Code session every `gh` call
# inside it runs sandboxed and fails, and that is deliberate: these are
# admin changes, so a session does not get to make them. Setup, not a
# standing tool: rerun it after a change to the required checks (the seed
# skill deleted, a workspace conversion), and delete it with SETUP.md in
# the release ceremony.
set -euo pipefail

usage() {
  awk 'NR > 3 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"
  exit "${1:-2}"
}

mode=check
app_client_id=""
app_key=""
while [ $# -gt 0 ]; do
  case $1 in
    --check) mode=check ;;
    --apply) mode=apply ;;
    --app-client-id) [ $# -ge 2 ] || usage; app_client_id=$2; shift ;;
    --app-key) [ $# -ge 2 ] || usage; app_key=$2; shift ;;
    -h | --help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
  shift
done
if [ "${app_client_id:+x}" != "${app_key:+x}" ]; then
  echo "--app-client-id and --app-key go together" >&2
  exit 2
fi
if [ -n "$app_key" ]; then
  if [ ! -r "$app_key" ]; then echo "cannot read $app_key" >&2; exit 2; fi
  if [ "$mode" != apply ]; then
    echo "--app-client-id and --app-key set secrets, so they need --apply" >&2
    exit 2
  fi
  # Absolute before the cd below, so a path relative to the caller still reads.
  app_key="$(cd "$(dirname "$app_key")" && pwd)/$(basename "$app_key")"
fi

cd "$(git rev-parse --show-toplevel)"
if ! repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1); then
  echo "gh cannot read this repo: $repo" >&2
  exit 1
fi

# The jobs a PR runs that gate a merge. Semver preview, the full mutation
# run and the auto-merge workflow's two jobs stay off on purpose (SETUP.md,
# "Branch protection"). Skill version guard exists only while skills/ does.
required_checks() {
  printf '%s\n' \
    "MSRV Check" \
    "Lint" \
    "Test on ubuntu-latest" \
    "Test on macos-latest" \
    "Test on windows-latest" \
    "License & Dependency Check" \
    "Supply Chain Review" \
    "Mutation Testing (diff)"
  if [ -d skills ]; then echo "Skill version guard"; fi
}

# Every tag pattern release.yml triggers on, so the ruleset covers each.
# Blank and comment lines inside the list are skipped and a trailing
# comment is cut, since a pattern missed here is a tag the ruleset leaves
# open. A shape this does not read (a flow list, other indentation) yields
# no patterns, which check_ruleset reports as UNREAD.
tag_patterns() {
  awk '
    /^on:/ { on = 1; next }
    on && /^[^ #]/ { exit }
    on && /^    tags:/ { tags = 1; next }
    tags && /^[[:space:]]*(#|$)/ { next }
    tags && /^      - / {
      sub(/^      - /, ""); sub(/[[:space:]]+#.*$/, ""); gsub(/["'"'"']/, "")
      sub(/[[:space:]]+$/, ""); print; next
    }
    tags { exit }
  ' .github/workflows/release.yml
}

status=0
detail=""

report() { printf '%-8s%s\n' "$1" "$2"; }
fail() { report "$1" "$2"; status=1; }

# run_item <label> <check> <fix> [async|force]
# A check returns 0 when the setting is right, 1 when it is off, 2 when it
# could not be read, and leaves a reason in $detail. A fix returns 0 when
# GitHub took the change, 3 when it needs input this run was not given; an
# empty fix means there is nothing to set, so the item reports as a plain run
# does. `async` trusts the fix's response instead of re-reading, for a
# setting GitHub applies in the background. `force` runs the fix under
# --apply even when the check passes.
# A check or fix runs on the left of `||`, so errexit is off inside it.
run_item() {
  local label=$1 check=$2 fix=$3 opt=${4:-} rc=0
  detail=""
  $check || rc=$?
  case $rc in
    0) if [ "$mode" != apply ] || [ "$opt" != force ]; then report ok "$label"; return; fi ;;
    2) fail UNREAD "$label: $detail"; return ;;
  esac
  if [ "$mode" != apply ] || [ -z "$fix" ]; then
    fail DRIFT "$label${detail:+: $detail}"; return
  fi
  detail=""; rc=0
  $fix || rc=$?
  case $rc in
    0) ;;
    3) fail DRIFT "$label: $detail"; return ;;
    *) fail FAILED "$label: $detail"; return ;;
  esac
  if [ "$opt" = async ]; then
    report set "$label (GitHub applies it in the background; --check confirms)"
    return
  fi
  detail=""; rc=0
  $check || rc=$?
  if [ $rc -eq 0 ]; then
    report set "$label"
  else
    fail FAILED "$label: still off after the change${detail:+ ($detail)}"
  fi
}

# Run a mutating gh call; on failure its stderr becomes $detail. Stdin
# (a heredoc or a file redirected onto the call) reaches gh.
gh_set() { detail=$(gh "$@" 2>&1 >/dev/null); }

# missing_from <have>: the names on stdin not in <have>, comma-joined.
missing_from() {
  local have=$1 name missing=""
  while IFS= read -r name; do
    printf '%s\n' "$have" | grep -qxF "$name" || missing="$missing${missing:+, }$name"
  done
  printf '%s' "$missing"
}

# --- Issues (the advisory monitor files its tracking issue) ---------------
check_issues() {
  local out
  out=$(gh api "repos/$repo" --jq .has_issues 2>&1) || { detail=$out; return 2; }
  [ "$out" = true ] && return 0
  detail="Issues are off"; return 1
}
fix_issues() { gh_set api -X PATCH "repos/$repo" -F has_issues=true; }

# --- Pull requests: auto-merge and head-branch deletion -------------------
check_pr_settings() {
  local out
  out=$(gh api "repos/$repo" --jq '"\(.allow_auto_merge) \(.delete_branch_on_merge)"' 2>&1) || { detail=$out; return 2; }
  [ "$out" = "true true" ] && return 0
  detail="allow_auto_merge and delete_branch_on_merge are $out"; return 1
}
fix_pr_settings() {
  gh_set api -X PATCH "repos/$repo" -F allow_auto_merge=true -F delete_branch_on_merge=true
}

# --- Secret scanning and push protection -----------------------------------
check_secret_scanning() {
  local out
  out=$(gh api "repos/$repo" --jq '"\(.security_and_analysis.secret_scanning.status) \(.security_and_analysis.secret_scanning_push_protection.status)"' 2>&1) || { detail=$out; return 2; }
  [ "$out" = "enabled enabled" ] && return 0
  if [ "$out" = "null null" ]; then
    detail="security_and_analysis is not readable (needs admin on the repo)"; return 2
  fi
  detail="secret scanning and push protection are $out"; return 1
}
fix_secret_scanning() {
  gh_set api -X PATCH "repos/$repo" --input - <<'JSON'
{"security_and_analysis": {"secret_scanning": {"status": "enabled"}, "secret_scanning_push_protection": {"status": "enabled"}}}
JSON
}

# --- Private vulnerability reporting ---------------------------------------
check_private_reporting() {
  local out
  out=$(gh api "repos/$repo/private-vulnerability-reporting" --jq .enabled 2>&1) || { detail=$out; return 2; }
  [ "$out" = true ] && return 0
  detail="off"; return 1
}
fix_private_reporting() { gh_set api -X PUT "repos/$repo/private-vulnerability-reporting"; }

# --- Dependabot alerts (204 on, 404 "disabled" off) ------------------------
check_alerts() {
  local out
  if out=$(gh api "repos/$repo/vulnerability-alerts" 2>&1); then return 0; fi
  case $out in
    *"Vulnerability alerts are disabled"*) detail="off"; return 1 ;;
    *) detail=$out; return 2 ;;
  esac
}
fix_alerts() { gh_set api -X PUT "repos/$repo/vulnerability-alerts"; }

# --- Dependabot security updates (needs alerts on first) -------------------
# With alerts off this read may fail; that is off, not unreadable.
check_security_updates() {
  local out rc=0
  if ! out=$(gh api "repos/$repo/automated-security-fixes" --jq .enabled 2>&1); then
    check_alerts || rc=$?
    if [ "$rc" -eq 1 ]; then detail="off (Dependabot alerts are off)"; return 1; fi
    detail=$out; return 2
  fi
  [ "$out" = true ] && return 0
  detail="off"; return 1
}
fix_security_updates() { gh_set api -X PUT "repos/$repo/automated-security-fixes"; }

# --- Code scanning: CodeQL default setup ------------------------------------
check_codeql() {
  local out
  out=$(gh api "repos/$repo/code-scanning/default-setup" --jq .state 2>&1) || { detail=$out; return 2; }
  [ "$out" = configured ] && return 0
  detail="default setup is $out"; return 1
}
fix_codeql() { gh_set api -X PATCH "repos/$repo/code-scanning/default-setup" -f state=configured; }

# --- Release-tag ruleset -----------------------------------------------------
ruleset_name="release tags"
# This repo's own rulesets only: an inherited org ruleset of the same name
# cannot be updated here. The first of any duplicates is the one checked.
ruleset_id() {
  gh api "repos/$repo/rulesets?includes_parents=false" \
    --jq "[.[] | select(.name == \"$ruleset_name\") | .id] | first // empty"
}
# ruleset_want <patterns>
ruleset_want() {
  local includes
  includes=$(printf '%s\n' "$1" | sed 's|^|refs/tags/|' | LC_ALL=C sort | paste -sd, -)
  echo "tag active $includes creation,deletion,update RepositoryRole:5:always"
}
# A workflow reads `+` and `?` as quantifiers and a leading `!` as a
# negation; a ruleset matches them as fnmatch characters. Copied across, such
# a pattern misses the tags it names while the check still reads ok, so it
# is reported unreadable and the ruleset is left alone.
check_ruleset() {
  local id have want odd patterns
  patterns=$(tag_patterns)
  if [ -z "$patterns" ]; then
    detail="no tag patterns found under on.push.tags in release.yml"; return 2
  fi
  odd=$(printf '%s\n' "$patterns" | grep -E '[+?]|^!' | paste -sd, -) || :
  if [ -n "$odd" ]; then
    detail="release.yml tag patterns a ruleset would read differently: $odd; set the ruleset by hand"
    return 2
  fi
  want=$(ruleset_want "$patterns")
  id=$(ruleset_id 2>&1) || { detail=$id; return 2; }
  if [ -z "$id" ]; then detail="no ruleset named \"$ruleset_name\""; return 1; fi
  have=$(gh api "repos/$repo/rulesets/$id" --jq '[.target, .enforcement,
      (.conditions.ref_name.include | sort | join(",")),
      ([.rules[].type] | sort | join(",")),
      ([.bypass_actors[] | "\(.actor_type):\(.actor_id):\(.bypass_mode)"] | sort | join(","))]
      | join(" ")' 2>&1) || { detail=$have; return 2; }
  [ "$have" = "$want" ] && return 0
  detail="have \"$have\", want \"$want\""; return 1
}
fix_ruleset() {
  local id includes method=POST path="repos/$repo/rulesets"
  includes=$(tag_patterns | sed 's|.*|"refs/tags/&"|' | paste -sd, -)
  id=$(ruleset_id 2>&1) || { detail=$id; return 1; }
  if [ -n "$id" ]; then method=PUT; path="$path/$id"; fi
  gh_set api -X "$method" "$path" --input - <<JSON
{
  "name": "$ruleset_name",
  "target": "tag",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": [$includes], "exclude": []}},
  "rules": [{"type": "creation"}, {"type": "update"}, {"type": "deletion"}],
  "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]
}
JSON
}

# --- Required checks have all reported on main --------------------------------
# A required check that never reports holds every PR forever, so main is
# protected only once each of them has reported on its HEAD.
reported_on_main() {
  gh api "repos/$repo/commits/main/check-runs?per_page=100" --jq '.check_runs[].name'
}
check_reported() {
  local reported missing
  reported=$(reported_on_main 2>&1) || { detail=$reported; return 2; }
  missing=$(required_checks | missing_from "$reported")
  [ -z "$missing" ] && return 0
  detail="never reported on main's HEAD: $missing; push main, or fix the list in this script"; return 1
}

# --- Branch protection on main --------------------------------------------------
protection_want() {
  echo "$(required_checks | LC_ALL=C sort | paste -sd'|' -) false false false false true false"
}
check_protection() {
  local have want
  want=$(protection_want)
  if ! have=$(gh api "repos/$repo/branches/main/protection" --jq '[
      ((.required_status_checks.checks // []) | map(.context) | sort | join("|")),
      .required_status_checks.strict,
      .enforce_admins.enabled,
      .allow_force_pushes.enabled,
      .allow_deletions.enabled,
      .required_conversation_resolution.enabled,
      (.required_pull_request_reviews != null)
    ] | map(tostring) | join(" ")' 2>&1); then
    case $have in
      *"Branch not protected"*) detail="main is not protected"; return 1 ;;
      *) detail=$have; return 2 ;;
    esac
  fi
  [ "$have" = "$want" ] && return 0
  detail="have \"$have\", want \"$want\""; return 1
}
fix_protection() {
  local checks rc=0
  check_reported || rc=$?
  case $rc in
    0) ;;
    1) detail="waits on the required checks to report on main (the line above)"; return 3 ;;
    *) return 1 ;;
  esac
  checks=$(required_checks | sed 's|.*|{"context": "&"}|' | paste -sd, -)
  gh_set api -X PUT "repos/$repo/branches/main/protection" --input - <<JSON
{
  "required_status_checks": {"strict": false, "checks": [$checks]},
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON
}

# --- Merge App: the two Dependabot secrets -------------------------------------
# Given the App's flags (which need --apply), the secrets are written even
# when both exist (run_item's `force`), so a new key can be rolled out to
# every repo before the old one is deleted on the App's page.
check_app_secrets() {
  local out missing
  out=$(gh secret list --app dependabot --json name --jq '.[].name' 2>&1) || { detail=$out; return 2; }
  missing=$(printf '%s\n' AUTOMERGE_APP_CLIENT_ID AUTOMERGE_APP_PRIVATE_KEY | missing_from "$out")
  [ -z "$missing" ] && return 0
  detail="missing Dependabot secrets: $missing"; return 1
}
fix_app_secrets() {
  if [ -z "$app_client_id" ]; then
    detail="missing; install the merge App on this repo, then pass --app-client-id and --app-key"
    return 3
  fi
  gh_set secret set AUTOMERGE_APP_CLIENT_ID --app dependabot --body "$app_client_id" || return 1
  gh_set secret set AUTOMERGE_APP_PRIVATE_KEY --app dependabot <"$app_key"
}

echo "$repo ($mode)"
run_item "Issues on" check_issues fix_issues
run_item "Allow auto-merge, delete head branches" check_pr_settings fix_pr_settings
run_item "Secret scanning and push protection" check_secret_scanning fix_secret_scanning
run_item "Private vulnerability reporting" check_private_reporting fix_private_reporting
run_item "Dependabot alerts" check_alerts fix_alerts
run_item "Dependabot security updates" check_security_updates fix_security_updates
run_item "CodeQL default setup" check_codeql fix_codeql async
run_item "Ruleset \"$ruleset_name\" on release.yml's tags" check_ruleset fix_ruleset
run_item "Required checks have reported on main" check_reported ""
run_item "Branch protection on main" check_protection fix_protection
run_item "Merge App secrets (Dependabot)" check_app_secrets fix_app_secrets "${app_client_id:+force}"
report manual "Merge App installed on this repo: the App's page > Install App (gh's token cannot read installations)"
report manual "Dependabot malware alerts: Settings > Security and quality > Advanced Security > Dependabot > Malware alerts"
exit $status
