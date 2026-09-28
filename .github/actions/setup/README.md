# Dependency mode

The setup action defaults to `sibling-overrides: 'true'`, preserving the existing
workspace integration behavior. It clones the sibling sources selected by
Superwork and installs Cargo path overrides.

A portable project with exact git revisions and a committed Cargo.lock can set
`sibling-overrides: 'false'`. Toolchain, assembler and cache setup still run,
but no Superwork installation, sibling cloning or Cargo source overrides occur.
Cargo then resolves the project's own dependency declarations. Use `--locked`
when the command should also reject lockfile updates.

This matters for coordinated codec PRs: replacing a pinned AVIF adapter with
one sibling checkout while replacing its pinned native encoder with a different
revision can remove the very API that the adapter was written against.
