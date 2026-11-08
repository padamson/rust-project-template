#!/usr/bin/env bash
#
# Stream GitHub Actions results for one commit: one line per job as it
# reaches a terminal state, one line per workflow when it finishes, then
# exit. Built to be driven by an agent's background monitor, but it reads
# fine in a terminal too.
#
# Usage:
#   ./scripts/ci-watch.sh                   # the current HEAD
#   ./scripts/ci-watch.sh <sha|ref>         # a specific commit
#   ./scripts/ci-watch.sh --poll 15         # poll every 15s (default 30)
#   ./scripts/ci-watch.sh --timeout 600     # give up after 10 minutes (default 3600)
#
# Exits 0 when every job and run passed, 1 when one failed, 2 when the
# watcher could not run (a bad flag or ref, no `gh` or no login for it, or
# no answer from GitHub before the timeout), and 3 when the timeout passed
# with runs still going.
#
# Flags, not an env-var prefix: the sandbox exclusion below matches the
# command line as written, and `TIMEOUT=600 ./scripts/ci-watch.sh` is not
# the excluded command, so it runs sandboxed and every `gh` call fails.
# POLL and TIMEOUT in the environment still set the defaults for a terminal.
#
# Why this is a script and not a loop written inline:
#
# The Claude Code sandbox matches `excludedCommands` against the top-level
# command line. `gh` on its own is excluded and works; `gh` inside a `for`
# or `while` loop is NOT matched, so the whole invocation stays sandboxed
# and every call fails on the read-denied ~/.config/gh -- silently, if the
# loop swallows errors. Excluding this script instead unsandboxes the whole
# process tree, and the `gh` it spawns inherits that, the same route
# `git push` takes for SSH. `.claude/settings.json` carries the exclusion.
#
# Every terminal state is reported, not just successes: a silent watcher
# looks identical to a passing one, which is the failure mode this replaces.
# The counts are taken from the current state on every poll, not
# accumulated, so a run that is re-run mid-watch and goes green is reported
# green, and its new job results are printed as they land.
set -uo pipefail

POLL="${POLL:-30}"
TIMEOUT="${TIMEOUT:-3600}"
REF=HEAD
# A usage error exits 2, never 1 or 3: 1 means a job failed and 3 that CI
# outlasted the timeout, and a caller branching on the code would report
# one of those when the watcher never ran.
usage() { echo "ci-watch: $1" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --poll) [ $# -ge 2 ] || usage "$1 needs a value"; POLL="$2"; shift 2 ;;
    --timeout) [ $# -ge 2 ] || usage "$1 needs a value"; TIMEOUT="$2"; shift 2 ;;
    --poll=*) POLL="${1#*=}"; shift ;;
    --timeout=*) TIMEOUT="${1#*=}"; shift ;;
    # The header only: from its first line of text to the first line
    # that is not a comment.
    -h|--help) awk 'NR > 2 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    -*) usage "unknown flag $1" ;;
    *) REF="$1"; shift ;;
  esac
done
# secs FLAG VALUE: a whole number of seconds, with no leading zero, since
# shell arithmetic reads 0600 as octal and aborts on 09.
secs() {
  case "$2" in ''|*[!0-9]*|0*) usage "$1 takes a whole number of seconds, not '$2'" ;; esac
}
secs --poll "$POLL"
secs --timeout "$TIMEOUT"

# The commit, not the ref's own object: an annotated tag names a tag
# object, and runs are listed by the commit it points to.
SHA="$(git rev-parse "$REF^{commit}")" || exit 2
SHORT="${SHA:0:7}"
command -v gh > /dev/null || { echo "ci-watch: gh is not installed" >&2; exit 2; }
DEADLINE=$(( $(date +%s) + TIMEOUT ))

# What the last `gh` call printed on stderr, shown when it fails.
GH_ERR=$(mktemp "${TMPDIR:-/tmp}/ci-watch.XXXXXX") || exit 2
trap 'rm -f "$GH_ERR"' EXIT

# Lines already printed: "|<run>/<job>/<conclusion>|" for a job,
# "|<run>/<conclusion>|" for a run, and the call, code and message for a
# failed `gh` call, so a re-run's new result prints again and a failure
# that repeats on every poll prints once.
seen=""

# gh_failed WHAT CODE: report a failed `gh` call with what it printed. gh
# exits 4 when it has no login, which no amount of waiting fixes, so that
# stops the watch. Anything else is retried on the next poll, since it may
# be a network blip. That includes a sandboxed `gh`, which exits 1 on the
# read-denied ~/.config/gh and so ends at the deadline, not at once.
gh_failed() {
  local said
  said=$(sed -n 's/^./  gh: &/p' "$GH_ERR")
  if [ "$2" -eq 4 ]; then
    printf 'ci-watch: gh has no login; run '\''gh auth login'\'' or set GH_TOKEN\n%s\n' "$said" >&2
    exit 2
  fi
  local key="|$1/$2/$said|"
  case "$seen" in *"$key"*) return ;; esac
  seen="$seen$key"
  printf 'ci-watch: %s failed (exit %s), retrying every %ss\n%s\n' "$1" "$2" "$POLL" "$said"
}

# The conclusions that pass, for a job and for a run alike.
is_green() {
  case "$1" in success|skipped|neutral) return 0 ;; *) return 1 ;; esac
}

# Set once `gh run list` answers. A watch that never got an answer did
# not see CI at all, so its deadline is "could not run", not a timeout.
reached=0

while :; do
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    if [ "$reached" -eq 0 ]; then
      echo "ci-watch: never reached GitHub for $SHORT" >&2
      exit 2
    fi
    echo "ci-watch: TIMEOUT waiting on $SHORT"
    exit 3
  fi

  # A failed call is told apart from "no runs for this commit yet".
  # `--commit` filters on the server, so an older commit is found however
  # many runs have landed since. Scheduled runs are left out: they land on
  # whatever commit main's tip was that day, and an old one that failed
  # says nothing about the commit being watched.
  ids=$(gh run list --commit "$SHA" --limit 100 --json databaseId,event \
        --jq '.[] | select(.event != "schedule") | .databaseId' 2>"$GH_ERR") ||
    { gh_failed "gh run list" "$?"; sleep "$POLL"; continue; }
  reached=1

  if [ -z "$ids" ]; then
    echo "ci-watch: no workflow runs for $SHORT yet"
    sleep "$POLL"
    continue
  fi

  pending=0
  failures=0
  bad_runs=0
  for id in $ids; do
    # One call per run: each finished job, then the run's own state. A call
    # that fails leaves the run pending for this poll.
    view=$(gh run view "$id" --json jobs,status,conclusion,workflowName --jq '
        (.jobs[] | select(.conclusion != null and .conclusion != "")
          | "JOB\t\(.conclusion)\t\(.name)"),
        "RUN\t\(.status)\t\(.conclusion // "-")\t\(.workflowName)"' 2>"$GH_ERR") ||
      { gh_failed "gh run view $id" "$?"; pending=$((pending + 1)); continue; }
    while IFS=$'\t' read -r kind a b c; do
      case "$kind" in
        JOB)
          conclusion="$a" name="$b"
          is_green "$conclusion" || failures=$((failures + 1))
          key="|$id/$name/$conclusion|"
          case "$seen" in *"$key"*) ;; *) seen="$seen$key"; echo "$conclusion  $name" ;; esac
          ;;
        RUN)
          status="$a" conclusion="$b" workflow="$c"
          if [ "$status" != "completed" ]; then
            pending=$((pending + 1))
            continue
          fi
          # A run can fail with no failed job: an invalid workflow file is a
          # startup_failure with no jobs at all.
          is_green "$conclusion" || bad_runs=$((bad_runs + 1))
          key="|$id/$conclusion|"
          case "$seen" in *"$key"*) ;; *) seen="$seen$key"; echo "RUN DONE: $workflow => $conclusion" ;; esac
          ;;
      esac
    done <<< "$view"
  done

  if [ "$pending" -eq 0 ]; then
    if [ "$failures" -gt 0 ] || [ "$bad_runs" -gt 0 ]; then
      echo "ci-watch: $SHORT finished with $failures failing job(s) in $bad_runs failed run(s)"
      exit 1
    fi
    echo "ci-watch: $SHORT all green"
    exit 0
  fi

  sleep "$POLL"
done
