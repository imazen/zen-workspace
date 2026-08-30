#!/usr/bin/env python3
"""patch-conflict-audit — find cross-repo [patch] disagreements in the zen crate tree.

PROTOTYPE. This should be folded into `cargo superwork check`, which already does
the adjacent version-consistency analysis. It is committed here because it detects
three things nothing else currently reports, and because the evidence in
WORKSPACE_STRUCTURE_2026-08-30.md was produced with it.

What it reports
---------------
1. CONFLICTS      one crate patched to different sources by different repos
                  (e.g. zenanalyze: path in jxl-encoder, floating git in zenjxl)
2. FLOATING       git patches with no rev/tag/branch -- a push to the patched repo
                  can turn an unrelated repo red with no commit in it
3. INERT          a path patch whose on-disk version cannot satisfy the requirement
                  it is meant to override. Cargo silently falls back to the registry
                  and emits only "patch ... was not used in the crate graph".
                  This is how jxl-encoder ended up building registry zenjxl-decoder
                  0.3.10 while a comment claimed it was path-patched to the sibling.

Read-only by default. `--emit-config PATH` writes a unified [patch.crates-io] table
suitable for a shared .cargo/config.toml (see the doc, step 2).

Usage
-----
    python3 scripts/patch-conflict-audit.py [--root DIR]... [--emit-config PATH]

Exit status: 1 if any conflict or inert patch was found, else 0.
"""

from __future__ import annotations
import argparse, os, sys, tomllib
from collections import defaultdict

DEFAULT_ROOTS = ["/Users/lilith/work", "/Users/lilith/work/zen"]


def repo_roots(roots):
    """Yield (repo_dir, root_manifest) for each canonical repo, skipping scratch worktrees."""
    seen = set()
    for base in roots:
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if "--" in name:            # scratch worktree convention
                continue
            d = os.path.join(base, name)
            if os.path.islink(d) or not os.path.isdir(d):
                continue
            real = os.path.realpath(d)
            if real in seen:            # symlink aliases (work/butteraugli -> zen/butteraugli)
                continue
            m = os.path.join(d, "Cargo.toml")
            if os.path.isfile(m):
                seen.add(real)
                yield d, m


def load(path):
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except Exception:
        return None


def describe(spec, repo_dir):
    """Return (comparable_key, absolute_spec) for a patch entry."""
    if "path" in spec:
        p = os.path.normpath(os.path.join(repo_dir, spec["path"]))
        return ("path", p), {"path": p}
    if "git" in spec:
        url = spec["git"].rstrip("/")
        if url.endswith(".git"):
            url = url[:-4]
        pin = spec.get("rev") or spec.get("tag") or spec.get("branch") or "<default-branch>"
        return ("git", url, pin), dict(spec)
    return ("other", repr(sorted(spec.items()))), dict(spec)


def crate_version(manifest_dir):
    """Version of the package rooted at manifest_dir, or None.

    Handles `version = { workspace = true }` by walking up to the owning
    workspace root and reading [workspace.package].version -- the same
    inheritance rule whose mishandling produces superwork check's 72
    false-positive path errors.
    """
    d = load(os.path.join(manifest_dir, "Cargo.toml"))
    if not d:
        return None
    v = d.get("package", {}).get("version")
    if isinstance(v, str):
        return v
    if isinstance(v, dict) and v.get("workspace") is True:
        cur = os.path.dirname(os.path.abspath(manifest_dir))
        while len(cur) > 1:
            wd = load(os.path.join(cur, "Cargo.toml"))
            if wd and "workspace" in wd:
                wv = wd["workspace"].get("package", {}).get("version")
                return wv if isinstance(wv, str) else None
            cur = os.path.dirname(cur)
    return None


def req_satisfied(req: str, version: str) -> bool:
    """Cheap caret-semver check: does `version` satisfy requirement `req`?

    Deliberately conservative -- only handles the bare/caret forms that dominate
    this tree. Anything else returns True so we never cry wolf.
    """
    req = req.strip()
    if not req or req[0] in "=<>~*":
        return True
    req = req.lstrip("^")
    try:
        r = [int(x) for x in req.split(".")]
        v = [int(x) for x in version.split("-")[0].split(".")]
    except ValueError:
        return True
    r += [0] * (3 - len(r))
    v += [0] * (3 - len(v))
    # caret: leftmost non-zero component must match, and version >= req
    lead = next((i for i, x in enumerate(r) if x), 2)
    return r[lead] == v[lead] and v >= r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", action="append", default=None,
                    help="directory containing repos (repeatable)")
    ap.add_argument("--emit-config", metavar="PATH",
                    help="write a unified [patch.crates-io] table to PATH")
    args = ap.parse_args()
    roots = args.root or DEFAULT_ROOTS

    entries = defaultdict(list)     # crate -> [(repo_dir, spec)]
    requirements = defaultdict(list)  # crate -> [(manifest, req)]

    repos = list(repo_roots(roots))
    for repo_dir, manifest in repos:
        d = load(manifest)
        if d is None:
            continue
        for _registry, tbl in d.get("patch", {}).items():
            for crate, spec in tbl.items():
                if isinstance(spec, dict):
                    entries[crate].append((repo_dir, spec))
        # collect requirements on patched crates from every manifest in the repo
        for dirpath, dirnames, filenames in os.walk(repo_dir):
            dirnames[:] = [x for x in dirnames
                           if x not in ("target", ".git", ".jj", "node_modules")]
            if "Cargo.toml" not in filenames:
                continue
            md = load(os.path.join(dirpath, "Cargo.toml"))
            if md is None:
                continue
            for sect in ("dependencies", "dev-dependencies", "build-dependencies"):
                for crate, spec in (md.get(sect) or {}).items():
                    ver = spec.get("version") if isinstance(spec, dict) else spec
                    if isinstance(ver, str):
                        requirements[crate].append(
                            (os.path.join(dirpath, "Cargo.toml"), ver))

    conflicts, floating, inert, unified = [], [], [], {}

    for crate, lst in sorted(entries.items()):
        by_key = defaultdict(list)
        for repo_dir, spec in lst:
            key, resolved = describe(spec, repo_dir)
            by_key[key].append(os.path.basename(repo_dir))
            unified.setdefault(crate, resolved)
            if "git" in spec and not any(k in spec for k in ("rev", "tag", "branch")):
                floating.append((os.path.basename(repo_dir), crate, spec["git"]))
        if len(by_key) > 1:
            conflicts.append((crate, dict(by_key)))
            for key in by_key:                       # prefer a local path source
                if key[0] == "path":
                    unified[crate] = {"path": key[1]}
                    break
        # inert check: a path patch that cannot satisfy a stated requirement
        for key in by_key:
            if key[0] != "path":
                continue
            ondisk = crate_version(key[1])
            if not ondisk:
                continue
            for manifest, req in requirements.get(crate, []):
                if not req_satisfied(req, ondisk):
                    inert.append((crate, req, ondisk, key[1], manifest))

    w = sys.stdout.write
    w("=" * 78 + "\n  CONFLICTS -- one crate, different sources in different repos\n" + "=" * 78 + "\n")
    if not conflicts:
        w("  (none)\n")
    for crate, by_key in conflicts:
        w(f"\n  {crate}: {len(by_key)} different sources\n")
        for key, repos_ in by_key.items():
            w(f"     {key}\n        declared by: {', '.join(sorted(set(repos_)))}\n")

    w("\n" + "=" * 78 + "\n  FLOATING -- git patches with no rev/tag/branch\n" + "=" * 78 + "\n")
    if not floating:
        w("  (none)\n")
    for repo, crate, url in sorted(set(floating)):
        w(f"  {repo:<18} {crate:<22} {url}\n")

    w("\n" + "=" * 78 + "\n  INERT -- path patch cannot satisfy the requirement; cargo uses the registry\n" + "=" * 78 + "\n")
    if not inert:
        w("  (none)\n")
    for crate, req, ondisk, path, manifest in sorted(set(inert)):
        w(f"  {crate}: requires {req!r} but {path} is {ondisk}\n"
          f"     -> patch is silently ignored; see {manifest}\n")

    w(f"\n  scanned {len(repos)} repos, {len(entries)} patched crates, "
      f"{sum(len(v) for v in entries.values())} patch entries\n")

    if args.emit_config:
        os.makedirs(os.path.dirname(os.path.abspath(args.emit_config)) or ".", exist_ok=True)
        with open(args.emit_config, "w") as f:
            f.write("# Generated by scripts/patch-conflict-audit.py -- do not hand-edit.\n")
            f.write("# Shared dev patch table. Cargo discovers this by walking up from the\n")
            f.write("# cwd, so it also reaches nested standalone sub-workspaces (fuzz/, apidoc/)\n")
            f.write("# that inherit nothing from their parent repo.\n")
            f.write("[patch.crates-io]\n")
            for crate, spec in sorted(unified.items()):
                body = ", ".join(f'{k} = "{v}"' for k, v in spec.items())
                f.write(f"{crate} = {{ {body} }}\n")
        w(f"\n  wrote {len(unified)} entries to {args.emit_config}\n")

    return 1 if (conflicts or inert) else 0


if __name__ == "__main__":
    sys.exit(main())
