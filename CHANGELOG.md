# Changelog

## [Unreleased]

### QUEUED BREAKING CHANGES

None.

### Fixed

- Resolve research `zensim` and `zensim-regress` CI checkouts from `imazen/zensimx`
  after the repository split. This preserves the zensim 0.3.0
  `deprecated-profiles` dependency used by zencodecs; metric settings and
  regression expectations are unchanged.

## Portable consumer CI

The reusable Rust workflow accepts `sibling_overrides: false` to validate a
consumer's committed dependency graph. The setup action then skips workspace
checkout, superwork installation and sibling path overrides, while retaining
toolchain, assembler and cache setup. The default remains true for existing
callers. This resolves zenpipe's unsupported workflow-input startup failure.
