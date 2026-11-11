# Setup Checklist

After creating a repo from this template, complete these steps.

## Automated (already in the template)

- [x] GitHub Actions CI: test, security, release workflows, a daily advisory monitor
- [x] Dependabot: weekly cargo and GitHub Actions updates, auto-merged behind the required checks
- [x] Pre-commit hooks via prek
- [x] cargo-deny configuration (the one advisory ignore list)
- [x] Tracked Claude Code sandbox settings (`.claude/settings.json`)
- [x] An agent skill scaffold under `skills/` (hidden from installers until you ship it), with its version guard
- [x] CHANGELOG scaffold
- [x] CLAUDE.md with development commands

## Search and replace

- [ ] Replace `my-project` with your project name in `Cargo.toml`, `README.md`, and `CLAUDE.md`
- [ ] Replace `OWNER/REPO` with your GitHub path in `Cargo.toml` and `CHANGELOG.md`
- [ ] Replace `Your Name` with your name in `Cargo.toml`, and `Paul Adamson` in `LICENSE-MIT`
- [ ] Decide about `skills/my-project`: ship it under your crate's name, or delete it (see "Agent skill" below)
- [ ] Update `description`, `categories`, and `keywords` in `Cargo.toml`
- [ ] Update `README.md` with your project description and usage
- [ ] Update `CLAUDE.md` with project-specific context
- [ ] Strip `<!-- Template users: ... -->` and similar meta-comments from `README.md` and `CLAUDE.md` after the placeholder substitutions

## GitHub settings

`scripts/github-settings.sh` sets the repository settings no file in the
tree can carry, and reports what it could not set. Run it from your own
terminal. In a Claude Code session every `gh` call inside it runs
sandboxed and fails, on purpose: these are admin changes to the repo, so
a session does not get to make them. It needs admin on the repo and a
`gh` token with the `repo` scope (`gh auth login`'s default); no extra
scope.

```bash
./scripts/github-settings.sh              # report, change nothing
./scripts/github-settings.sh --apply      # set whatever is off
./scripts/github-settings.sh --apply \
    --app-client-id <id> --app-key <app>.private-key.pem
                                          # also write the merge App's secrets
```

It prints one line per setting: `ok`, `set` (changed by this run),
`DRIFT`, `FAILED`, `UNREAD` (`gh` could not read it, so never counted as
drift), or `manual` (no API it can use). It exits 0 when nothing is
`DRIFT`, `FAILED` or `UNREAD`.

- [ ] **Create the merge App** (one App serves every repo you own; skip
  this if you have it). **Settings > Developer settings > GitHub Apps >
  New GitHub App**: any name and homepage URL, webhook off, and repository
  permissions **Contents**, **Pull requests** and **Workflows** set to
  read and write. Workflows is there because Dependabot's actions bumps
  edit files under `.github/workflows/`. Note the **Client ID**.
- [ ] **Install the App** on this repo: the App's page > **Install App** >
  your account > **Only select repositories**. Then, on the App's page,
  generate a private key for this repo and save the `.pem`.
- [ ] **Run the script with `--apply` and the App's flags**, then once
  more with no flags. A pass is exit 0 with only `ok` and `manual` lines.
- [ ] **Turn on Dependabot malware alerts**, which the script cannot
  reach: **Settings > Security and quality > Advanced Security >
  Dependabot > Malware alerts**.
- [ ] **Delete the local `.pem`** once the secret is set. Don't delete the
  key on the App's page: every other repo the App is installed on holds
  that key as its secret, and deleting it breaks auto-merge in all of
  them. An App holds several keys at once, so a new repo gets a new key.
  To retire a key on purpose, set the new one as the secret in every repo
  first (the script with `--apply` and the App's flags writes the secrets
  even when they exist), then delete the old one.
- [ ] **Never add the App to the branch protection bypass list.** Its
  merges would then skip the required checks.
- [ ] **Prove it.** With Dependabot security updates on and an advisory
  open, a PR arrives right away, since security updates ignore the
  cooldown; otherwise wait for the weekly run. The merged PR's
  `merged_by` should be the App's bot, and its merge commit should have
  the full set of push runs on `main`.

Rerun the script with `--apply` after any change to the required checks
or the release tags: deleting the seed skill (it requires `Skill version
guard` only while `skills/` exists), or adding a per-crate tag prefix to
`release.yml` after converting to a workspace (it reads the patterns from
that file).

The rest of this section is what the script sets and why. The script
holds the values, so a change to them (a required check added or renamed)
is made there; if this section and the script disagree, the script is what
GitHub gets.

### Branch protection on `main`

**Every PR-triggered job is required.** The required checks are the
entire merge gate for Dependabot: `dependabot-auto-merge.yml` enables
auto-merge on every Dependabot PR, and it merges the moment these are
green. The push run on `main` afterwards tests the merged tree but cannot
stop the merge. A job left off this list (Supply Chain Review is the
classic omission) means a bump merges with that job red.

- `MSRV Check` — cheap; catches accidental use of post-MSRV features
- `Lint` — fmt, clippy, doctest, cargo doc (ubuntu-only)
- `Test on ubuntu-latest`, `Test on macos-latest`, `Test on windows-latest`
- `License & Dependency Check`, `Supply Chain Review`
- `Mutation Testing (diff)`, `Skill version guard`

`Semver preview` stays off the list. It is the early warning for the
release's semver gate, and on 0.x a deliberate breaking change turns it
red until the release that bumps the version, which would block every
merge in between. `dependabot-auto-merge.yml`'s two jobs, `Hold a PR that
edits this workflow` and `Enable auto-merge`, stay off too: they are the
merge machinery, not checks on the change, and the hold's red is what
marks a PR you merge by hand (Dependabot auto-merge, below).

**"Require branches to be up to date" stays off** (`strict: false`).
With it on, the second green Dependabot PR of the week is stale the moment
the first merges, auto-merge never updates branches, and Dependabot only
rebases on a conflict, so PRs sit blocked until someone clicks "update
branch" and every rebase re-runs CI. Off, each green PR merges once. The
residual risk (two green PRs that conflict semantically without
conflicting in git) is negligible for Dependabot: cargo PRs always collide
on `Cargo.lock` and get rebased and re-tested, and an actions bump beside
a cargo bump touches disjoint files.

**Protection waits until every required check has reported on `main`.**
A required check that never reports holds every PR forever. The script
reports any that has not reported on `main`'s HEAD on a line of its own,
and `--apply` refuses to protect `main` until they all have. On a fresh
repo the initial push's runs already satisfy it, so protection can go on
at once.

### Release-tag ruleset

A tag ruleset named `release tags` restricts creation, update and
deletion of release tags, with the Repository admin role as the only
bypass. The merge App's token can push a tag, a tag pushed with it starts
`release.yml` (one pushed with `GITHUB_TOKEN` would not), and the release
publishes through Trusted Publishing, so without the ruleset a leaked App
key could release any commit by tagging it. It covers every pattern under
`on.push.tags` in `release.yml`. Your own `git push origin main --tags`
still works through the admin bypass.

### Release environment

`release.yml`'s publish job runs in an environment named `release`, and
the script lets only tags matching `on.push.tags` deploy to it (no
branches). The crates.io trusted publisher checks the repository and the
workflow's filename, not the ref a run came from, and the App's Workflows
permission lets it push a branch carrying its own `release.yml`, one that
runs on that push or on a tag the ruleset does not cover. Without the
environment, that run could mint a publish token. With it, the run either
names the environment and its deployment policy refuses it, or leaves the
environment out and gets a token crates.io refuses, because the publisher
names `release` (crates.io Trusted Publishing, below). The App can change
neither the environment nor the ruleset: both need admin. Name the
environment in the publisher only once the script reports it `ok`: a run
that names an environment GitHub does not have creates it open to every
branch.

To approve each publish by hand, add required reviewers to the
environment (**Settings > Environments > release**). The script keeps
reviewers and a wait timer set there.

### Dependabot auto-merge

`dependabot-auto-merge.yml` enables auto-merge with a GitHub App's token.
A merge made with the default `GITHUB_TOKEN` starts no workflows, so
`main` would never get a push run for a Dependabot merge: nothing would
test the tree two sibling bumps leave behind, and push-only jobs would not
run. Until the App and its secrets exist, minting the token fails, so
every Dependabot PR shows a red **Enable auto-merge** check and waits for
you to merge it by hand. That check is not required, so the red is a
reminder, not a block. A Dependabot PR that edits
`dependabot-auto-merge.yml` itself shows a red **Hold a PR that edits this
workflow** check instead, and **Enable auto-merge** is skipped: a bump of
the token action would otherwise run with the App's key before review.
Read the bump and merge it by hand. `dependabot.yml` keeps that action out
of the weekly actions group, so its bump arrives as a PR of its own and
the rest of the week's action bumps still merge on their own.

The script turns on **Allow auto-merge** (with it off, the workflow's `gh
pr merge --auto` fails and nothing merges) and **Automatically delete
head branches**. It sets the App's Client ID and private key as
**Dependabot secrets**, not Actions secrets, because a Dependabot-triggered
run can read only Dependabot secrets.

The private key mints tokens for every repo the App is installed on, so
install it only where everyone with write access could be trusted with
all of them; a repo with outside collaborators gets its own App.

### Code security

The script turns on private vulnerability reporting, Dependabot alerts,
Dependabot security updates, CodeQL default setup, secret scanning, and
push protection. Issues stay on, since the advisory monitor files its
tracking issue there.

### crates.io Trusted Publishing

The release workflow publishes with a short-lived token minted from
GitHub's OIDC identity for this repo and this workflow. There is no
`CARGO_REGISTRY_TOKEN` secret to create, leak, or rotate.

- [ ] On crates.io, for your crate: **Settings > Trusted Publishing > Add a GitHub publisher** with owner `OWNER`, repository `REPO`, workflow `release.yml`, and environment `release` (Release environment, above).

  A crate that has never been published has no settings page yet. Publish
  the first version from your machine with a token scoped to
  `publish-new`, then add the trusted publisher and revoke the token; every
  later release goes through the workflow.

  If the publisher is missing or misnamed, the `Authenticate to crates.io`
  step fails and the run is red. That is the intended signal. The workflow
  has no "skip if not configured" path and no `continue-on-error` on the
  publish, because both turn a broken release into a green run with no
  crate.

- [ ] Once the crate is on crates.io, tell cargo-vet it is this repo's own
  code. From the first publish on, `cargo vet` matches the path crate to
  the published version and fails every push ("non-crates.io-fetched
  packages match published crates.io versions") until the crate has a
  policy. Add to `supply-chain/config.toml`, once per published crate:

  ```toml
  [policy.<crate>]
  audit-as-crates-io = false
  ```

## Local setup

### Install tools

```bash
cargo install cargo-nextest cargo-deny cargo-vet cargo-mutants cargo-semver-checks prek
```

If any `cargo install` fails with a rustc version mismatch (`requires rustc X.Y.Z or newer, while the currently active rustc version is ...`), run `rustup update stable` — or run `cargo install` from outside any directory containing a `rust-toolchain.toml` override. `cargo install` uses the *active* toolchain, which is directory-scoped when a toolchain file is present in the working tree.

### Enable pre-commit hooks

A committed `.pre-commit-config.yaml` does nothing until the hook is
installed, and skipping the install fails silently (your first commit
just goes in unhooked). Run these by hand once per clone, from your own
terminal: the install writes into `.git/hooks`, which the Claude Code
sandbox protects, so a session can't do it for you.

- [ ] Install the hook:

  ```bash
  prek install --overwrite
  ```

  `--overwrite` replaces any pre-existing `.git/hooks/pre-commit` from the
  legacy Python `pre-commit`. Without it, prek keeps the old hook at
  `.git/hooks/pre-commit.legacy` and runs both, so every check fires twice.
- [ ] Verify the hook is installed: `head -2 .git/hooks/pre-commit` shows
  `# File generated by prek` on its second line.
- [ ] Verify the hooks work, which also proves cargo-deny, nextest, and
  the rest are installed:

  ```bash
  prek run --all-files
  ```

### Verify everything works

```bash
cargo build
cargo nextest run
cargo deny check
```

### Initialize cargo-vet

See the cargo-vet section below.

## cargo-vet initialization

Until `cargo vet init` has run, both the pre-commit `cargo vet` hook and
the CI `Supply Chain Review` job print a skip message and pass, so the
first commit and push of a new repo are not blocked on this section.

After your first `cargo build`, initialize supply chain auditing:

```bash
cargo vet init
cargo vet import bytecode-alliance
cargo vet import embark-studios
cargo vet import fermyon
cargo vet import google
cargo vet import isrg
cargo vet import mozilla
cargo vet import zcash
```

`cargo vet import <name>` resolves the canonical URL for each known
trusted org — no need to pin a URL. Together, these seven imports
absorb the bulk of common transitive dependencies (in one dogfooding
run on a real project they converted 142 exemptions into real audits
without any maintainer work).

If your crate has no third-party dependencies yet, `cargo vet` passes immediately with nothing to audit. The imports above pre-seed trusted audit sets so that when you add your first dependency, the audits are already in place — you can safely defer the `cargo vet import ...` commands until then.

### Transitively trust publishers your imported orgs trust

The orgs you imported have already named individual publishers they
trust. `cargo vet trust` extends that trust to your tree, with no audit
work of your own. Which publishers you trust is your decision, so the
template ships no list. The steps below find the ones your imports
already agree on:

1. After the imports, run `cargo vet suggest`. Under a crate it
   recommends auditing, a `NOTE:` line names any publisher your imported
   orgs trust (*e.g.*, "isrg, mozilla, and bytecode-alliance trust
   rust-lang-owner").
2. Trust each publisher those lines name, at `safe-to-deploy`:

   ```bash
   cargo vet trust --all <publisher> --criteria safe-to-deploy
   ```

   Without `--criteria` the command prompts, and it offers the level of
   the exemptions it replaces. That is `safe-to-run` while the tree holds
   only dev-dependencies, and `safe-to-run` trust stops covering a crate
   once it becomes a normal dependency.
3. A crate with more than one publisher is skipped, with a warning to
   rerun with `--allow-multiple-publishers` (and an error if nothing else
   was left to trust). Rerun with the flag. It lets `--all` trust the
   publisher for any crate they have published even one version of,
   which can be more than you meant, so read the `[[trusted.*]]` entries
   it added to `supply-chain/audits.toml` before you commit.
4. Run `cargo vet` and follow its prompts to exempt what is left.

On the template's own tree (as of November 2026) the trust step takes
`cargo vet` from 5 audited and 8 exempted to 10 and 3, and in one
dogfooding run on a real project it took 304 exemptions to 237.

A login stops covering a crate once its owner publishes through
crates.io Trusted Publishing. `cargo vet` then reports the publisher as
`github:<owner>/<repo>`, and the login's entry no longer matches the new
versions. Trust that identity for the crate instead:

```bash
cargo vet trust jiff github:BurntSushi/jiff --criteria safe-to-deploy
```

### Per-PR workflow for unvetted entries

**Never auto-regenerate exemptions in CI.** A Supply Chain Review
failure on a Dependabot PR is the *signal* that new unvetted code is
arriving — pause and decide before merging. Auto-regenerating
rubber-stamps every upstream change and defeats the point of
`cargo vet`.

The fix lands on `main`, not on the PR branch. Dependabot's rebase is a
force-push that drops any commit added to its branch, and a human push
makes the auto-merge job skip the PR, so it would need a hand merge
anyway. For each unvetted entry in a failing PR, on `main`:

- **`cargo vet certify <crate> <version>`** — gold standard. Read the
  diff (`diff -ru` of the two versions under `~/.cargo/registry/src/`),
  then attest.
- **An exemption for the new version** — bronze standard. Acceptable
  for patch bumps from known publishers; not for new transitives or
  majors. Add it by hand to `supply-chain/config.toml`, beside the old
  version's entry rather than in place of it, so `main` stays green
  until the PR merges. (`cargo vet regenerate exemptions` on `main`
  never sees the PR's version.)
- **Reject** if the diff looks sketchy.

Push, comment `@dependabot rebase` on the PR so its next run picks up
the audits, and run `cargo vet prune` once it merges.

## Agent skill

`skills/my-project/` is the shape of the skill this crate would ship:
the directory `npx skills add OWNER/REPO` installs into a consumer's
repo, so an agent there knows how to use the crate. As scaffolded it is
hidden from installers (`metadata.internal: true`) and nothing loads it.
Decide now:

- [ ] **Ship it.** Rename the directory to your crate name, remove the
  `internal` line from `SKILL.md`, write it for an agent that has never
  seen the crate, and fill `references/`. Every later content edit bumps
  `metadata.version`; the pre-commit hook and the `Skill version guard`
  CI job refuse one that doesn't. Keep the "Agent skill" block in
  `README.md`.

  Only if this repo uses its own crate (examples, an e2e suite, docs that
  exercise it) is it worth auto-loading the skill in-repo too. Claude
  Code discovers project skills at `.claude/skills/` alone, so add one
  tracked symlink and un-ignore it:

  ```bash
  ln -s ../../skills/<name> .claude/skills/<name>
  echo '!/.claude/skills/<name>' >> .gitignore
  ```

- [ ] **Don't ship one.** Delete `skills/`,
  `scripts/check-skill-version-bumped.sh`, the `skill-version-bumped`
  hook in `.pre-commit-config.yaml`, the `skill-version` job in
  `test.yml`, and the "Agent skill" block in `README.md`, then rerun
  `./scripts/github-settings.sh --apply` to drop `Skill version guard`
  from the required checks.

Skills of the tools this crate depends on are the other direction, and
CLAUDE.md covers them: `npx skills add <owner>/<repo>` once per clone,
content gitignored, pin tracked in `skills-lock.json`.

## Keeping `target/` under control

A project that builds many permutations (default, `--all-features`,
per-target, mutation testing, fuzzing) accumulates tens of gigabytes
under `target/`, most of it incremental-compilation cache with no
payoff outside a single edit-rebuild loop.

- **Sweep periodically.** `cargo-sweep` is unmaintained, so use a
  plain `find` (or `cargo-clean-all`, which is maintained). This lists
  every `target/` under `~/src` that Cargo made (its `CACHEDIR.TAG` says
  so) and in which nothing was modified in 30 days. A build that compiles
  anything counts as use, but a no-op build writes nothing, so a repo you
  only build or run, with no pull, lockfile change or toolchain update in
  that time, is listed too. Read the list, then add `&& rm -rf "$1"`
  inside the quotes:

  ```bash
  find ~/src -type d -name target -prune -exec sh -c \
    'grep -qs "created by cargo" "$1/CACHEDIR.TAG" && [ -z "$(find "$1" -mtime -30 -print -quit)" ] && echo "$1"' _ {} \;
  ```
- **Consider turning incremental off** once the permutation count grows:
  `[build] incremental = false` in `.cargo/config.toml`. CI already has
  it off (`Swatinem/rust-cache` sets `CARGO_INCREMENTAL=0`).
- **Build scripts that download large assets** (drivers, models,
  fixtures) must not write them into `OUT_DIR`: its path carries a
  per-toolchain, per-feature hash, so every permutation re-downloads and
  keeps its own copy. Write to a stable, version-keyed path outside
  `target/` (env-selectable, defaulting to `OUT_DIR` for zero-config
  local use), give the script a skip-download env var for compile-only
  jobs like MSRV, and cache that path in CI with its own `actions/cache`
  keyed on the asset version. `Swatinem/rust-cache` deliberately does not
  cache workspace crates' build-script output.

## Converting to a workspace

The template ships a single crate on purpose: one `Cargo.toml`, one
`src/lib.rs`, every CI invocation already carrying `--workspace` so
nothing needs to change when a second crate appears. Convert when a
second crate has a reason to exist (a `-core` library behind a CLI,
a proc-macro crate, a separate binary), not before.

1. `mkdir -p crates/<name>` and `git mv src tests crates/<name>/`.
2. Turn the root `Cargo.toml` into a virtual manifest:
   `[workspace] members = ["crates/*"]`, `resolver = "3"`, a
   `[workspace.package]` block holding `edition`, `rust-version`,
   `license`, `repository`, `authors`, and a `[workspace.dependencies]`
   table. Move the crate's own `[package]` to `crates/<name>/Cargo.toml`
   with `edition.workspace = true` and friends.
3. `.cargo/mutants.toml`: `examine_globs = ["crates/*/src/**/*.rs"]`.
   `deny.toml` already allows versionless path deps between private
   workspace members.
4. `release.yml` semver-checks and publishes every crate whose `publish`
   is not `false`, each at its own version, skipping a version already on
   crates.io. If one crate depends on another, replace the publish step's
   `cargo metadata` list with the crates in dependency order, since cargo
   resolves each from crates.io. Each published crate needs its own
   trusted-publisher entry, naming environment `release` like the first,
   and its own `audit-as-crates-io = false` policy. A `v*` tag releases
   every publishable crate whose version is not yet on crates.io; the
   tag's version has to match at least one of them, and it names the
   archives and picks the CHANGELOG section for the release notes. A crate new to the workspace is published by hand once,
   like the first, before its trusted publisher can exist.
5. Run `cargo nextest run --workspace`, `cargo clippy --all-targets
   --all-features -- -D warnings`, `cargo deny check`, and
   `./scripts/mutants.sh --working --list` before committing; the last
   one confirms the mutants config still resolves files.

## Reporting the build commit from `--version`

For a binary people install from source (`cargo install --git`, or
`--path`), make `--version` say which commit it was built from when it
is not a tagged release. Three cases: no git available (a crates.io
install) prints the bare crate version; HEAD exactly at the tag
`v<version>` prints the bare version, since that is the release; anything
else prints `<version> (<short sha>)`. No dirty-tree marker: nothing
re-runs the build script on an uncommitted edit, so it would be wrong as
often as right.

Add a `build.rs`:

```rust
fn main() {
    let version = std::env::var("CARGO_PKG_VERSION").unwrap_or_default();
    let build_id = match git_short_sha() {
        Some(sha) if !at_release_tag(&version) => format!("{version} ({sha})"),
        _ => version,
    };
    println!("cargo:rustc-env=CRATE_VERSION_WITH_BUILD={build_id}");

    // Freshness: `.git/HEAD` covers checkouts and branch switches; the
    // branch's ref file covers commits. Use `../../.git` from a workspace
    // member.
    let git_dir = std::path::Path::new(".git");
    if !git_dir.exists() {
        return;
    }
    println!("cargo:rerun-if-changed=.git/HEAD");
    if let Ok(head) = std::fs::read_to_string(git_dir.join("HEAD"))
        && let Some(reference) = head.strip_prefix("ref: ")
        && git_dir.join(reference.trim()).exists()
    {
        println!("cargo:rerun-if-changed=.git/{}", reference.trim());
    }
}

fn git_short_sha() -> Option<String> {
    let out = std::process::Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let sha = String::from_utf8(out.stdout).ok()?.trim().to_string();
    (!sha.is_empty()).then_some(sha)
}

fn at_release_tag(version: &str) -> bool {
    std::process::Command::new("git")
        .args(["describe", "--exact-match", "--tags", "HEAD"])
        .stderr(std::process::Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .is_some_and(|tag| tag.trim() == format!("v{version}"))
}
```

With clap derive: `#[command(version = env!("CRATE_VERSION_WITH_BUILD"))]`.

Test the shape, not the environment, so the same test passes in a dev
checkout and in a tagged release build: the output starts with
`CARGO_PKG_VERSION`, and any suffix matches exactly ` (<7+ hex digits>)`.

## Release ceremony (final step — cut vX.Y.Z)

Only run this after every box above is checked and your first feature PR has merged.

1. Promote `## [Unreleased]` in `CHANGELOG.md` to `## [X.Y.Z] - YYYY-MM-DD` (use today's date); leave a fresh `## [Unreleased]` above it for future work.
2. Update the compare links at the bottom of `CHANGELOG.md`:
   - Change `[Unreleased]` to `https://github.com/OWNER/REPO/compare/vX.Y.Z...HEAD`.
   - Add `[X.Y.Z]: https://github.com/OWNER/REPO/releases/tag/vX.Y.Z`.
3. Update the version in `Cargo.toml` to `X.Y.Z`.
4. Remove this file and the settings script — you won't need them again:
   `git rm SETUP.md scripts/github-settings.sh`.
5. Commit, tag, push:
   ```bash
   git add Cargo.toml CHANGELOG.md
   git commit -m "Release vX.Y.Z"
   git tag vX.Y.Z
   git push origin main --tags
   ```
6. Watch the Release workflow. On success, verify end-to-end:
   ```bash
   cargo install <crate> && <crate> --version
   ```
