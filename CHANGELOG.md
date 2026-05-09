# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Initial project scaffold
- `.mutants.toml.example` with scoping guidance to keep `cargo mutants` runs tractable on real downstreams
- New `Lint` job in `test.yml` (ubuntu-only) covering fmt, clippy, doctest, and `cargo doc`
- Comments in `security.yml`, `.pre-commit-config.yaml`, and `deny.toml` documenting the `cargo audit --ignore` pattern keyed off `deny.toml`'s `[advisories] ignore` as source of truth
- CLAUDE.md / SETUP.md note on `prek install --overwrite` to avoid double-firing legacy pre-commit hooks
- MSRV-job comment on stubbing `include_bytes!` build artifacts via `touch` for downstreams that embed generated files

### Changed
- `test.yml` matrix (ubuntu/macos/windows) now runs only `cargo build` + `cargo nextest run`; lint and doc steps moved to the new ubuntu-only `Lint` job

[Unreleased]: https://github.com/OWNER/REPO/commits/main
