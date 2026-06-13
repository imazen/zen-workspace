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

| Box | Type | Cores/RAM | Arch | ~cost (monthly cap) |
|---|---|---|---|---|
| `zen-fuzz-arm` | cax31 | 8 / 16 GB | arm64 | ~€15/mo |
| `zen-fuzz-x86` | cpx42 | 8 / 16 GB | x86_64 | ~€30/mo |

Persistent (never auto-killed). Labeled `purpose=fuzz` so jobdash's `group=<RUN>`
fleet-kill never matches them. SSH: `root@<ip>` with `~/.ssh/zen-arm-dev`.

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

### Recommended workstation crons

```cron
*/30 * * * *  cd ~/work/zen-workspace/fuzz-farm && ./triage-crashes.sh        >> /tmp/fuzz-triage.log 2>&1
0    */6 * * * cd ~/work/zen-workspace/fuzz-farm && ./sync-tree.sh        $HOSTS >> /tmp/fuzz-sync.log 2>&1
17   3  */4 * * cd ~/work/zen-workspace/fuzz-farm && ./refresh-r2-creds.sh $HOSTS >> /tmp/fuzz-cred.log 2>&1
```

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

28 libFuzzer crates / ~146 targets are auto-discovered (anything with
`fuzz/fuzz_targets/*.rs` + `libfuzzer-sys` in `fuzz/Cargo.toml`). The lone AFL
crate (`rawloader-fork`) is skipped — it needs `cargo afl`, a separate harness;
fold it in later if wanted. `sync-tree.sh` also ships `~/work/{archmage,magetypes}`
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
| `launch-boxes.sh` | workstation | create + provision boxes (billable) |
| `kill-boxes.sh` | workstation | delete boxes |
