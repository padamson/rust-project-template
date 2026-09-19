---
name: my-project
description: Use when working with my-project — replace this line with the one-sentence trigger that tells an agent when to load this skill, naming the files, commands, or tasks that identify the situation.
license: MIT OR Apache-2.0
metadata:
  version: "0.1.0"
---

# my-project

<!--
Template users: this directory is what `npx skills add OWNER/REPO` installs
into a consumer's repo. Write it for an agent that has never seen your
crate: what the crate does, the two or three ways it is used, and the
mistakes a first use makes. Put long reference material (CLI surface,
directive tables, API listings) under `references/` and point at it from
here, so the body stays short enough to load on every trigger.

Bump `metadata.version` on every content change; the pre-commit hook and
the `Skill version guard` CI job both refuse an edit that leaves it alone.
If this crate will not ship a skill, delete `skills/`, the
`.claude/skills/my-project` symlink, `scripts/check-skill-version-bumped.sh`,
the `skill-version-bumped` hook, the `skill-version` CI job, and the
"Agent skill" block in README.md. SETUP.md lists these under the skill
checklist.
-->

## When to use

Describe the trigger conditions.

## How it works

Describe the crate's model in a few paragraphs, then link the details:

- [`references/usage.md`](references/usage.md): the API or CLI surface.
