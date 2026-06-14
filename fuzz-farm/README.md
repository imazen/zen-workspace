# fuzz-farm — continuous Hetzner fuzzing for every zen crate

Two persistent Hetzner boxes — one ARM, one x86 — that fuzz every zen crate's
libFuzzer targets around the clock, rotating constantly. They cooperatively grow
one shared corpus per target (arch-independent inputs help both), each catches
its own arch-specific crashes (NEON vs AVX, pointer width, codegen), and every
new crash is auto-filed as a GitHub issue from the workstation.

This complements the existing local `fuzz-nightly.sh` (a 5-min-per-target nightly
cron on the workstation): the farm is the *always-on* tier; the nightly stays as
a quick local sanity pass.

## Boxes

| Box | Type | Cores/RAM | Arch | Role | ~cost |
|---|---|---|---|---|---|
| `zen-fuzz-x86` | cpx42 | 8 / 16 GB | x86_64 | dedicated, disposable | ~€30/mo |
| `zen-arm-dev` | cax21 | 4 / 8 GB | arm64 | shared dev box (fuzzes on an 80 GB volume) | +~€3.5/mo (volume) |
| `zen-fuzz-arm` | cax31 | 8 / 16 GB | arm64 | optional dedicated (launch when CAX stock returns) | ~€15/mo |

**Labels: `fuzz=yes` = farm member** (resolved by sync-tree / refresh-r2-creds /
deploy.sh). **`purpose=fuzz` = dedicated, disposable** (only `kill-boxes.sh`
targets those, by name — never the shared dev box). ARM coverage currently runs
on the small dev box `zen-arm-dev`: its root disk is full of dev work, so the
fuzz tree + caches + `.cargo`/`.rustup` live on an attached 80 GB volume
(`/mnt/fuzz`, symlinked from `/root/work` + `/root/fuzz-farm`), at `fork=2` +
`MemoryMax=5G` so it stays responsive for dev/phone use. SSH: `root@<ip>` with
`~/.ssh/zen-arm-dev`. A separate dedicated `zen-fuzz-arm` (cax31) can still be
launched via `launch-boxes.sh arm` if you want more ARM throughput.

## How it works

```
                    workstation (~/work/zen = source of truth)
   sync-tree.sh ──rsync──┐                        ▲
   refresh-r2-creds.sh ──┤                        │ triage-crashes.sh (cron 30m)
   (cron)                ▼                         │  pull crashes, dedup,
              ┌── zen-fuzz-arm ──┐   ┌── zen-fuzz-x86 ──┐   file GitHub issues
              │ fuzz-rotate.sh   │   │ fuzz-rotate.sh   │   (imazen/lilith only)
              │ (systemd, always)│   │ (systemd, always)│
              └────────┬─────────┘   └────────┬─────────┘
                       └──────── R2: s3://zenfuzz ────────┘
                          corpus/<crate>/<target>/   (shared, both boxes)
                          crashes/<crate>/<target>/<arch>/<sig>/
```

**Box** (`fuzz-rotate.sh` under `zen-fuzz.service`, `Restart=always`): forever,
reshuffle all ~146 (crate,target) pairs; per target — pull shared corpus from R2,
fuzz `SLICE_SECS` (default 600) on all cores via `-fork=N -ignore_*=1`, push new
corpus back, and for any new artifact reproduce-once → upload repro + signature
to R2. Per-fork RSS is sized from RAM so a fork storm can't OOM the box. The box
holds **no GitHub token** and never files issues.

**Workstation**: `sync-tree.sh` rsyncs the always-buildable tree to the boxes
(source of truth — avoids git-clone path-dep skew across 60+ repos);
`triage-crashes.sh` (cron) pulls crashes, dedups by signature, maps each crate to
its repo from the local tree, and files an issue assigned to `lilith` for
`imazen/*` + `lilith/*` repos. Third-party repos (forks, upstream) are queued in
`needs-review.tsv`, never auto-posted.

## Bring-up

```bash
cd ~/work/zen-workspace/fuzz-farm
./launch-boxes.sh both            # create + provision (SPENDS MONEY)
HOSTS="root@$(hcloud server ip zen-fuzz-arm) root@$(hcloud server ip zen-fuzz-x86)"
./sync-tree.sh        $HOSTS      # seed the buildable tree (minutes, first time)
./refresh-r2-creds.sh $HOSTS      # push scoped R2 creds
for h in $HOSTS; do ssh -i ~/.ssh/zen-arm-dev $h systemctl start zen-fuzz; done
```

## Operate

```bash
# status / live log
ssh -i ~/.ssh/zen-arm-dev root@$(hcloud server ip zen-fuzz-arm) systemctl status zen-fuzz
ssh -i ~/.ssh/zen-arm-dev root@$(hcloud server ip zen-fuzz-arm) tail -f fuzz-farm/logs/rotate.log

# triage crashes -> issues (dry run first)
DRY_RUN=1 ./triage-crashes.sh
./triage-crashes.sh

# kill (stops billing; corpus/crashes safe in R2)
./kill-boxes.sh both
```

### Deployment

Scripts are version-controlled here (`zen-workspace/fuzz-farm`); the running copy
lives at `~/work/zenfuzz-farm/`, where the crons execute from (decoupled from the
repo checkout state). After committing+pushing an edit, redeploy everywhere with
one versioned command:

```bash
~/work/zenfuzz-farm/deploy.sh            # deploy origin/main to ops dir + every box, restart fuzzers
~/work/zenfuzz-farm/deploy.sh <git-ref>  # pin a specific commit/branch/tag
```

`deploy.sh` extracts the ref with `git archive` (no checkout — ignores any WIP in
the primary checkout), refreshes the ops dir, pushes the box-runtime files to
every `purpose=fuzz` box, restarts each `zen-fuzz`, and writes the deployed commit
to `DEPLOYED_VERSION` (ops dir + each box) so the live version is always visible.
First-time bootstrap (before deploy.sh is in the ops dir):
`git -C ~/work/zen-workspace archive origin/main fuzz-farm | tar -x --strip-components=1 -C ~/work/zenfuzz-farm`.

### Recommended workstation crons

`sync-tree.sh` and `refresh-r2-creds.sh` with no args auto-resolve every
`fuzz=yes` box, so a box is picked up automatically once it joins.

```cron
*/30 * * * *  cd ~/work/zenfuzz-farm && ./triage-crashes.sh   >> /tmp/fuzz-triage.log 2>&1
23  */6 * * *  cd ~/work/zenfuzz-farm && ./sync-tree.sh        >> /tmp/fuzz-sync.log   2>&1
37  4 */4 * *  cd ~/work/zenfuzz-farm && ./refresh-r2-creds.sh >> /tmp/fuzz-cred.log   2>&1
```

**ARM grab (armed):** `grab-arm-dev.sh` runs every 30 min and, the moment a
≥32 GB ARM box (cax41) is in stock, creates `zen-arm-xl` and provisions it as a
**dev box** (full mise toolchain via `setup-arm-box.sh`) that *also* fuzzes as a
niced background layer (dev stays primary), then self-disarms. It's labeled
`purpose=dev` (so `kill-boxes.sh` never touches it). Finish with a one-time
`claude` OAuth login on the box.
```cron
*/30 * * * * cd ~/work/zenfuzz-farm && ./grab-arm-dev.sh >> /tmp/fuzz-arm-grab.log 2>&1
```
`bringup-arm.sh` is the alternative: a *dedicated fuzz-only* ARM box (`zen-fuzz-arm`,
`purpose=fuzz`, disposable) — arm it instead of grab-arm-dev only if you want a
throwaway fuzzer rather than a dev box.

## Credentials

- **Hetzner**: `~/.config/hetzner/credentials` (`api_token=`), SSH key
  `zen-arm-dev-20260528` / `~/.ssh/zen-arm-dev`.
- **R2**: boxes get a **scoped, 7-day, single-bucket (`zenfuzz`), object-rw**
  temp cred minted by `refresh-r2-creds.sh` — the CF management token stays on
  the workstation. If the workstation is offline past the TTL, uploads pause and
  resume on the next refresh (fuzzing never stops; crashes stay on box disk).
  For full workstation-independence, mint a *permanent* bucket-scoped R2 token
  (R2 → Manage R2 API Tokens, scope to `zenfuzz`) and drop it in `r2.env` on each
  box instead — then the refresh cron isn't needed.
- **GitHub**: only on the workstation (`gh` as `lilith`). Boxes never see it.

## Tuning

Per-box env (set in `zen-fuzz.service`, then `systemctl daemon-reload && restart`):
`SLICE_SECS` (per-target slice), `FORKS` (default = nproc), `RSS_LIMIT_MB`
(default = (RAM−3GB)/forks), `FUZZ_TIMEOUT`.

## Coverage

28 libFuzzer crates / ~111 targets are discovered via the `crates.list` allow-list
× `cargo fuzz list` (registered `[[bin]]` targets only — so orphan/template files
like heic's stray `fuzz_target_1.rs` are skipped, not built-and-failed). Only
crates with `libfuzzer-sys` in `fuzz/Cargo.toml` qualify. The lone AFL crate
(`rawloader-fork`) is skipped — it needs `cargo afl`, a separate harness; fold it
in later if wanted. A target that fails to build (e.g. a bit-rotted one like
zentone's `fuzz_filmic_params`, which constructs a now-`#[non_exhaustive]` struct)
is logged and skipped, never blocking the rotation. `sync-tree.sh` also ships `~/work/{archmage,magetypes}`
for the path-dep graph; add to `FUZZ_EXTRA_REPOS` if a build fails on a missing
sibling.

## Files

| File | Runs on | Purpose |
|---|---|---|
| `fuzz-rotate.sh` | box | the continuous rotation runner |
| `zen-fuzz.service` | box | systemd unit (Restart=always) |
| `setup-fuzz-box.sh` | box | provision toolchain + install service |
| `sync-tree.sh` | workstation | rsync buildable tree to boxes |
| `refresh-r2-creds.sh` | workstation | mint + push scoped R2 creds |
| `triage-crashes.sh` | workstation | pull crashes, dedup, file issues |
| `deploy.sh` | workstation | versioned redeploy to ops dir + all boxes |
| `launch-boxes.sh` | workstation | create + provision dedicated fuzz boxes (billable) |
| `grab-arm-dev.sh` | workstation | (cron) grab a ≥32GB ARM box when in stock → dev box + niced fuzz |
| `bringup-arm.sh` | workstation | (alt) grab a dedicated fuzz-only ARM box |
| `kill-boxes.sh` | workstation | delete dedicated (purpose=fuzz) boxes |
