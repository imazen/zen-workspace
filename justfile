# Zen ecosystem recipes — run from the superworkspace root

# GitHub ecosystem dashboard (single GraphQL call)
gh-dashboard:
    cargo superwork gh-dashboard

# ── zen* inner-loop tools (bin/zen, see bin/README.md) ───────────────────
# No build step: single-file Python, stdlib only. Add bin/ to PATH to drop
# the `just` prefix and get `zenci`, `zenred`, … as bare commands.

# CI verdict per workflow across the tree — cancelled is NOT a pass
ci *ARGS:
    @{{justfile_directory()}}/bin/zen ci {{ARGS}}

# Only what is not passing
ci-fail *ARGS:
    @{{justfile_directory()}}/bin/zen ci --fail-only {{ARGS}}

# What is red right now: first error line + the commit that broke it
red *ARGS:
    @{{justfile_directory()}}/bin/zen red {{ARGS}}

# Is a commit actually on the trunk at origin? (`just pushed <sha> [repo]`)
pushed *ARGS:
    @{{justfile_directory()}}/bin/zen pushed {{ARGS}}

# Post-push sanity: on trunk AND non-empty AND touches what you expect
verify *ARGS:
    @{{justfile_directory()}}/bin/zen verify {{ARGS}}

# Audit .workongoing markers across every repo; find leaks
markers *ARGS:
    @{{justfile_directory()}}/bin/zen markers {{ARGS}}

# Largest unclaimed cargo target dirs (`just space --need 40G --reclaim`)
space *ARGS:
    @{{justfile_directory()}}/bin/zen space {{ARGS}}
