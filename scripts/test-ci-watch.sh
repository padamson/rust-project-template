#!/usr/bin/env bash
#
# Self-test for ci-watch.sh.
#
# A caller (an agent's background monitor, most often) acts on the
# watcher's exit code and reads its lines, so both are the contract: 0 all
# green, 1 a job or run failed, 2 the watcher could not run, 3 it timed
# out. A stub `gh` on PATH stands in for GitHub and answers only for the
# commit it is told about, so a watcher that asks about the wrong object
# finds no runs. The watcher runs from a scratch repo with an annotated
# tag, the ref most easily resolved to the wrong object.

set -euo pipefail

# A pre-commit hook inherits GIT_INDEX_FILE and friends from the commit
# that runs it, and the git calls below would then write the scratch
# repo's commit into that commit's index.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

here=$(cd "$(dirname "$0")" && pwd)
watcher="$here/ci-watch.sh"
# An explicit template: BSD mktemp does not take TMPDIR into account for a
# bare `-d`, so leaving it out puts the fixtures somewhere macOS may refuse.
work=$(mktemp -d "${TMPDIR:-/tmp}/ci-watch-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/repo"
repo="$work/repo"

# Signing and hooks off, whatever the user's global config says: the
# scratch commit and tag need neither, and a signing key may be out of
# reach.
g() {
    git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
        -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
g init -q
g commit -q --allow-empty -m seed
g tag -a v0.1.0 -m v0.1.0
commit=$(g rev-parse HEAD)

# Answers `gh run list --commit SHA` with one run when SHA is STUB_COMMIT
# and none otherwise, and `gh run view` with one job and its run, both
# concluding STUB_CONCLUSION. STUB_LIST_EXIT and STUB_VIEW_EXIT make that
# call fail, printing STUB_ERR. Output is what the watcher's --jq filters
# would leave, since the stub does not run them.
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/calls"
case "$1 $2" in
    "run list")
        if [ "${STUB_LIST_EXIT:-0}" -ne 0 ]; then echo "$STUB_ERR" >&2; exit "$STUB_LIST_EXIT"; fi
        while [ $# -gt 0 ]; do
            if [ "$1" = --commit ] && [ "$2" = "$STUB_COMMIT" ]; then echo 101; fi
            shift
        done
        ;;
    "run view")
        if [ "${STUB_VIEW_EXIT:-0}" -ne 0 ]; then echo "$STUB_ERR" >&2; exit "$STUB_VIEW_EXIT"; fi
        printf 'JOB\t%s\tbuild\n' "$STUB_CONCLUSION"
        printf 'RUN\tcompleted\t%s\tTest\n' "$STUB_CONCLUSION"
        ;;
    *) echo "stub gh: unexpected call: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$work/bin/gh"

failures=0

# fail NAME [CONTEXT_FILE]: report a failed check, indenting the context.
fail() {
    echo "FAIL: $1"
    if [ -n "${2:-}" ]; then sed 's/^/    /' "$2" | head -n 20; fi
    failures=$((failures + 1))
}

# watch [ENV=VALUE...] -- ARGS: run the watcher from the scratch repo with
# the stub first on PATH, stdout and stderr together in $work/out. The
# defaults are a commit with runs that pass, polled every second.
watch() {
    local env=(STUB_COMMIT="$commit" STUB_CONCLUSION=success STUB_ERR=)
    while [ "$1" != -- ]; do env+=("$1"); shift; done
    shift
    : > "$work/calls"
    status=0
    (cd "$repo" && env PATH="$work/bin:$PATH" STUB_DIR="$work" "${env[@]}" \
        "$watcher" --poll 1 "$@") > "$work/out" 2>&1 < /dev/null || status=$?
}

# expect NAME STATUS TEXT: the last watch exited STATUS and printed TEXT.
expect() {
    local name="$1" status_want="$2" text="$3"
    if [ "$status" -ne "$status_want" ]; then
        fail "$name: exit $status, expected $status_want" "$work/out"
    elif ! grep -qF -- "$text" "$work/out"; then
        fail "$name: output did not contain '$text'" "$work/out"
    else
        echo "ok: $name"
    fi
}

watch -- --timeout 5
expect "a commit whose runs pass exits 0" 0 "all green"

watch STUB_CONCLUSION=failure -- --timeout 5
expect "a failing job exits 1" 1 "1 failing job(s)"

watch -- --timeout 5 v0.1.0
expect "an annotated tag is watched at the commit it points to" 0 "all green"

watch STUB_COMMIT=none -- --timeout 1
expect "no runs before the deadline exits 3" 3 "TIMEOUT"

watch -- --bogus
expect "an unknown flag exits 2" 2 "unknown flag --bogus"

watch STUB_LIST_EXIT=1 STUB_ERR="HTTP 502: Bad Gateway" -- --timeout 3
expect "a run list that never succeeds exits 2 with what gh said" 2 "HTTP 502: Bad Gateway"
if [ "$(grep -c '^run list' "$work/calls")" -ge 2 ] && [ "$(grep -c 'HTTP 502' "$work/out")" -eq 1 ]; then
    echo "ok: a failure that repeats is printed once"
else
    cat "$work/calls" "$work/out" > "$work/context"
    fail "a failure that repeats was not polled twice and printed once (calls, then output)" "$work/context"
fi

# Once GitHub has answered, a run that cannot be read is a run still
# pending, so the deadline is a timeout.
watch STUB_VIEW_EXIT=1 STUB_ERR="HTTP 404: Not Found" -- --timeout 1
expect "a failed run view prints what gh said" 3 "HTTP 404: Not Found"

# Every tool the watcher needs but gh, so PATH can leave gh out.
mkdir "$work/nogh"
for tool in bash git date mktemp sed sleep rm; do
    ln -s "$(command -v "$tool")" "$work/nogh/$tool"
done
watch PATH="$work/nogh" -- --timeout 3
expect "no gh on PATH exits 2" 2 "gh is not installed"

# gh exits 4 when it has no login, which waiting cannot fix.
watch STUB_LIST_EXIT=4 STUB_ERR="To get started with GitHub CLI, please run:  gh auth login" -- --timeout 3
expect "gh with no login exits 2" 2 "gh auth login"
if [ "$(grep -c '^run list' "$work/calls")" -eq 1 ]; then
    echo "ok: gh with no login is asked once, not polled"
else
    fail "gh with no login was polled instead of asked once" "$work/calls"
fi

watch -- --help
expect "--help exits 0" 0 "Usage:"
if grep -qF "/usr/bin/env" "$work/out"; then
    fail "--help printed the shebang" "$work/out"
else
    echo "ok: --help leaves out the shebang"
fi
# Every comment line with text after the header's end: the script's first
# line that is not a comment.
awk 'body && /^# ./ { sub(/^# /, ""); print } !/^#/ { body = 1 }' "$watcher" > "$work/body"
if grep -Fxf "$work/body" "$work/out" > "$work/context"; then
    fail "--help printed comments from the script's body" "$work/context"
else
    echo "ok: --help stops at the end of the header"
fi

if [ "$failures" -ne 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
