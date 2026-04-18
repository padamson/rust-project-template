# Setup Checklist

After creating a repo from this template, complete these steps.

## Automated (already in the template)

- [x] GitHub Actions CI: test, security, release workflows
- [x] Dependabot: weekly cargo and GitHub Actions updates
- [x] Pre-commit hooks via prek
- [x] cargo-deny configuration
- [x] CHANGELOG scaffold
- [x] CLAUDE.md with development commands

## Search and replace

- [ ] Replace `my-project` with your project name in `Cargo.toml` and `README.md`
- [ ] Replace `OWNER/REPO` with your GitHub path in `Cargo.toml`
- [ ] Replace `Your Name` with your name in `Cargo.toml`
- [ ] Update `description`, `categories`, and `keywords` in `Cargo.toml`
- [ ] Update `README.md` with your project description and usage
- [ ] Update `CLAUDE.md` with project-specific context

## GitHub Settings (manual)

These settings cannot be configured via code and must be set in the GitHub UI.

### Repository settings

- [ ] **Settings > General > Features:** Enable "Issues" and "Projects" if not already
- [ ] **Settings > Branches > Branch protection:** Add rule for `main`:
  - Require a pull request before merging (optional for solo projects)
  - Require status checks to pass before merging: `Test on ubuntu-latest`, `Security Audit`, `License & Dependency Check`, `Supply Chain Review`
  - Require branches to be up to date before merging

### Code security

- [ ] **Settings > Code security:** Enable:
  - Dependabot alerts
  - Dependabot security updates
  - Code scanning (CodeQL) via default setup
  - Secret scanning
  - Push protection

### Secrets (for crates.io publishing)

- [ ] **Settings > Secrets and variables > Actions:** Add `CARGO_REGISTRY_TOKEN`
  - Generate at https://crates.io/settings/tokens
  - Scope: publish-update for your crate

### Environments (optional)

- [ ] Create `release` environment with required reviewers if you want manual approval before publishing

## Local setup

- [ ] Install prek: `cargo install prek`
- [ ] Install hooks: `prek install`
- [ ] Initialize cargo-vet: `cargo vet init` and import trusted audits
- [ ] Run initial checks: `cargo build && cargo nextest run && cargo deny check`

## cargo-vet initialization

After your first `cargo build`, initialize supply chain auditing:

```bash
cargo vet init
cargo vet import mozilla https://raw.githubusercontent.com/nickel-org/nickel.rs/refs/heads/main/nickel-supply-chain/audits.toml
cargo vet import google https://chromium.googlesource.com/chromiumos/third_party/rust_crates/+/refs/heads/main/cargo-vet/audits.toml?format=TEXT
```

Then exempt any unaudited dependencies:

```bash
cargo vet
# Follow the prompts to exempt crates
```
