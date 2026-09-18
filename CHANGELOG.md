# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- `scripts/mutants.sh` diffs a root commit against git's empty tree, so `Mutation Testing (diff)` tests the initial scaffold instead of failing with exit 128 on a repo's first push; a user-supplied base ref that does not resolve is now a hard error rather than a silent pass
- `scripts/mutants.sh --working` diffs uncommitted edits against `HEAD` (or a given ref), for gating a change before it is committed
- `scripts/mutants.sh` passes `--no-renames` to `git diff`, so a `git mv` produces a mutable diff instead of a green gate over unmutated code
- Pre-commit `cargo vet` hook: `files` regex now matches paths under `supply-chain/` (the end-anchored pattern matched nothing), and the hook skips until `cargo vet init` has run, mirroring the CI job
- `deny.toml`: `allow-wildcard-paths = true`, so versionless path deps of `publish = false` workspace members and dev-dependencies do not trip `wildcards = "deny"`
- CLAUDE.md: `--working` usage, the `-f <file>` trap, and the one-run-at-a-time rule for `mutants.out/`
- `Supply Chain Review` job checks for `supply-chain/audits.toml` before installing cargo-vet, so an uninitialized repo skips in seconds instead of building the tool first
- `dependabot-auto-merge.yml`: enables squash auto-merge on every Dependabot PR; the required status checks are the whole gate, since merges made with `GITHUB_TOKEN` trigger no push run on `main`
- Dependabot `cooldown` (7/14/7/3 days for cargo, 7 for actions) so bumps arrive after the cargo-vet import sets have audited them
- Dependabot groups for majors and for actions, plus a commented git-dependencies slot that must come first, so the weekly run opens at most four PRs and the auto-merge cascade (N PRs, O(N^2) CI runs) cannot start
- SETUP.md: require every PR-triggered job including `Mutation Testing (diff)`, and leave "require branches to be up to date" off, with the reasoning for both
- Initial project scaffold
- `.cargo/mutants.toml.example` with scoping guidance to keep `cargo mutants` runs tractable on real downstreams: `.cargo/` is the one path cargo-mutants reads (a root `.mutants.toml` is ignored silently) and the header says how to verify the config is live; `test_workspace = true` and no `--lib`, which skipped `tests/` integration targets and let cross-target kills survive; a commented nextest filterset as the speed lever and a commented `exclude_globs` for codegen output
- `test.yml` split: ubuntu-only `Lint` job covers fmt, clippy, doctest, and `cargo doc`; the cross-platform matrix (ubuntu/macos/windows) runs only `cargo build` + `cargo nextest run`
- Comments in `security.yml`, `.pre-commit-config.yaml`, and `deny.toml` documenting the `cargo audit --ignore` pattern keyed off `deny.toml`'s `[advisories] ignore` as source of truth
- CLAUDE.md / SETUP.md note on `prek install --overwrite` to avoid double-firing legacy pre-commit hooks
- MSRV-job comment on stubbing `include_bytes!` build artifacts via `touch` for downstreams that embed generated files
- Expanded `cargo vet import` list in SETUP.md to the seven well-known trusted orgs (bytecode-alliance, embark-studios, fermyon, google, isrg, mozilla, zcash), using the named-import form
- Per-PR workflow documentation in SETUP.md for handling Supply Chain Review failures on Dependabot PRs (never auto-regenerate exemptions in CI; certify vs. regenerate vs. reject)
- `cargo vet trust` section in SETUP.md covering transitive trust of publishers already certified by imported orgs (seanmonstar, BurntSushi, epage, kennykerr, Lokathor), including `--allow-multiple-publishers` guidance for flagship multi-maintainer packages
- `scripts/mutants.sh` wrapper for `cargo mutants --in-diff`, with project-specific pre-setup placeholder, defaulting to `HEAD~1..HEAD`
- Two-job mutation-testing setup in `security.yml`: a per-push/PR `mutation-testing-diff` job using `cargo mutants --in-diff` (typical runtime seconds-to-minutes), with `fetch-depth: 0` and PR/push base resolution; and a `mutation-testing` (full) job available via manual `workflow_dispatch` only — full-codebase runs don't scale to be scheduled
- `## Mutation testing` section in CLAUDE.md covering the local script + CI shape
- `/mutants.out/` and `/mutants.out.old/` added to `.gitignore`
- All Cargo cache steps in `test.yml`, `release.yml`, and `security.yml` switched from `actions/cache@v5` + manual key composition to `Swatinem/rust-cache@v2` + `shared-key`. Auto-derived key includes the rustc version (catches stale-binary panics across toolchain bumps), and pre-save cleanup keeps cache size in check. Release-job `shared-key` includes `matrix.target` so the two macOS cross-targets don't clobber each other.

[Unreleased]: https://github.com/OWNER/REPO/commits/main
