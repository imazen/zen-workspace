# Changelog

## [Unreleased]

### QUEUED BREAKING CHANGES

None.

### Fixed

- Resolve research `zensim` and `zensim-regress` CI checkouts from `imazen/zensimx`
  after the repository split. This preserves the zensim 0.3.0
  `deprecated-profiles` dependency used by zencodecs; metric settings and
  regression expectations are unchanged.
