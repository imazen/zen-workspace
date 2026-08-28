# fuzz-farm operational notes

Findings that are NOT in README.md. This file lives only in the ops dir; it
survives `deploy.sh` (which extracts tracked files over this dir but never
deletes extras). **Fold these into `imazen/zen-workspace:fuzz-farm/README.md`
when that repo is next touched** — see "Uncommitted drift" below for why that
did not happen here.

## 2026-07-30 — an unlabeled box is a SILENTLY dead farm member

`zen-fuzz-cx43` (created 2026-07-20, cx43/8-core/x86_64) was created with **no
Hetzner labels at all**. Every workstation cron resolves its hosts with
`hcloud server list -l fuzz=yes`, so all three skipped it:

- `refresh-r2-creds.sh` → its scoped R2 cred (minted 2026-07-17, 7-day TTL)
  **expired 2026-07-24** and was never rotated.
- `sync-tree.sh` → its source tree went stale.
- `deploy.sh` → it never received script updates.

**The failure is silent in both directions.** With no hosts resolved, the
scripts print `no fuzz boxes found` and `exit 0` — a successful-looking cron.
On the box, `fuzz-rotate.sh` wraps every R2 call in `|| true`, so an expired
credential does not stop or even warn the fuzzer: it kept fuzzing at full tilt
for 6 days while every `r2_pull_corpus` / `r2_push_corpus` / crash upload
silently 403'd (`SignatureDoesNotMatch`). `systemctl is-active` said `active`
and `rotate.log` looked perfectly healthy the whole time.

Cost of the gap: 6 days of corpus discovery not shared to R2 (or to the ARM
box), and 6 crash signatures that never reached triage. Those 6 were recovered
and uploaded on 2026-07-30; **all 6 normalize to already-filed issues, so no new
bug was lost** — only the evidence trail. Breakdown, for calibration on how much
a blind window actually costs:

| box sig | normalized | mapped issue | outcome |
|---|---|---|---|
| `02c3c934…` | panic `predict/directional.rs:90:13` | aom-decoder-rs#10 | OPEN → suppressed (known) |
| `d7f66155…` | panic `filter/deblock.rs:366:5` | aom-decoder-rs#11 | OPEN → suppressed (known) |
| `1803c795…` | timeout in `encode_decode` | zenrav1e#17 | CLOSED/COMPLETED, but resource sigs are never re-opened |
| `1c4907ce…` | timeout in `encode` | zenrav1e#13 | CLOSED/COMPLETED, same |
| `6d6a57a6…` | oom in `decode` | zenjxl-decoder#26 | CLOSED/NOT_PLANNED → suppressed |
| `c9e94722…` | oom in `fuzz_render` | zenextras#13 | OPEN → suppressed (known) |

Two traps when checking this yourself: (1) the box's `sig_hash` in
`~/fuzz-farm/state/meta-*.json` is **not** the ledger key — `triage-crashes.sh`
re-derives `sha256(crate_rel\ntarget\nnormalized_sig)[:16]` from the meta's
signature+trace, so grepping `filed-issues.tsv` for the box hash always misses.
(2) `ledger_hit_is_stale_closed` re-opens **panics only** — a `timeout in <t>` /
`oom in <t>` signature is coarse by design (any slow input for that target
collapses to one hash), so a closed-COMPLETED resource issue will not re-open
even when the crash postdates the close.

Fixed by labelling the box `arch=x86_64 fuzz=yes name=zen-fuzz-cx43 owner=lilith
purpose=fuzz` and re-running `refresh-r2-creds.sh`. (`purpose=fuzz` is safe:
`kill-boxes.sh` deletes by *name* — `zen-fuzz-arm` / `zen-fuzz-x86` — never by
label, so it will not touch this box.)

**When launching any farm box, verify membership immediately:**

```bash
hcloud server list -l fuzz=yes -o columns=name,ipv4     # must list the new box
ssh -i ~/.ssh/zen-arm-dev root@<ip> \
  'set -a; . ~/.config/zenfuzz/r2.env; set +a
   AWS_REGION=auto s5cmd --endpoint-url "$R2_ENDPOINT" ls "s3://$R2_BUCKET/corpus/" | head -3'
```

An empty/403 result means the box is fuzzing into a void. Worth hardening
later: have `fuzz-rotate.sh` log a loud warning when an R2 op fails, and have
the host-resolving scripts exit non-zero when they resolve zero hosts.

## 2026-07-30 — the farm now uses a PERMANENT R2 token (temp-cred cron disabled)

Both `fuzz=yes` boxes now hold a non-expiring, single-bucket (`zenfuzz`),
object-read-write R2 token at `~/.config/zenfuzz/r2.env`, so the farm no longer
depends on the workstation being alive to rotate credentials — the root cause of
the 6-day blind window above. The `37 4 */4 * *` `refresh-r2-creds.sh` cron is
**commented out**; re-enabling it would overwrite `r2.env` with a 7-day temp cred
and re-introduce the expiry. Crontab backups: `~/tmp/fuzzbackup/crontab-backup-*.txt`
and `/mnt/v/fuzzes/_farm/`.

- Token id / S3 access key: `5a859c21…`, created 2026-07-30, never expires.
  Raw value (needed to revoke) is in `~/.config/cloudflare/zenfuzz-token.json` (600);
  the S3 pair for provisioning new boxes is in
  `~/.config/cloudflare/zenfuzz-permanent.env` (600).
- Re-install to any new box: `install-permanent-r2-cred.sh` with
  `R2_PERM_ACCESS_KEY_ID` / `R2_PERM_SECRET_ACCESS_KEY` exported from that file.
- Revoke: dashboard, or `DELETE /accounts/<acct>/tokens/5a859c21…`.

### Cloudflare gotchas this cost time on — all verified live, none guessable

1. **`R2_API_TOKEN` cannot mint tokens.** It has R2 read + temp-cred-mint only;
   every token-management path returns `9109`. Neither can the three account
   tokens in `~/fun/weaver/.env`, nor the wrangler OAuth grant (expired, and its
   scopes carry nothing for token management). The token that *can* is in
   `~/.config/cloudflare/cf-token-mint` — it carries "Account API Tokens Write".
2. **Account-owned tokens 404-equivalent on the user endpoints.** `/user/tokens/verify`
   returns `1000 Invalid API Token` for a perfectly valid account-owned token;
   `/user/tokens/*` returns `9109 Valid user-level authentication not found`. Verify
   and create via `/accounts/<acct>/tokens*`. A token is not dead just because
   `/user/tokens/verify` rejects it — that misread nearly got four valid tokens
   written off.
3. **Resolve the permission group BY NAME, never by the id in the docs.** The
   published example labels `6a018a9f2fc74eb6b293b0c548f38b39` as "Workers R2
   Storage Bucket Item Write"; this account's live list reports that id as
   **Read**, with Write at `2efd5506f9c8494dacb1fa10a3e7d5b6`. Hardcoding the doc
   value mints a read-only key that lists fine and silently cannot push corpus.
4. **A freshly-minted R2 token is not immediately active.** The first probe
   seconds after creation failed to list the bucket; the identical call succeeded
   shortly after. `install-permanent-r2-cred.sh` now retries for ~2 min rather
   than treating propagation lag as a bad credential.
5. **`unset AWS_SESSION_TOKEN` in `r2.env` is load-bearing.** `fuzz-rotate.sh`
   sources that file into a long-lived shell each pass, so the session token from
   the previous *temp* cred would otherwise persist in the process and 403 every
   request against the new permanent key. The installer also restarts `zen-fuzz`.

The installer refuses to deploy an over-broad token: it probes that the cred can
read+write `zenfuzz` **and** is denied on `zentrain`, aborting otherwise.

## Seed corpora never reached the fuzzers

Repo-committed seeds (e.g. `zengif/fuzz/corpus/seed/*.gif`, git-tracked) do
reach a box — `sync-tree.sh`'s `overlay_canonical_fuzz` ships them via
`git archive` — but `fuzz-rotate.sh` fuzzes `$FUZZ_HOME/corpus/<key>`, i.e.
`~/fuzz-farm/corpus/`, and never looks at the repo's `fuzz/corpus/`. So those
seeds were carried to the box and then ignored.

Fix applied for zengif: the 17 seeds were uploaded into
`corpus/zengif/{fuzz_decode,fuzz_decode_streaming,fuzz_roundtrip}/` so the farm
actually uses them. Deliberately **not** `fuzz_limits` — that target takes a
structured `Arbitrary` `FuzzInput`, not raw GIF bytes. Other crates with
committed seeds likely have the same gap; check before assuming a seed is live.

## 2026-07-25 dev-32gb backup import

Corpora rescued from the decommissioned dev-32gb box were merged into
`s3://zenfuzz/corpus/`: zenavif +388, zenpng +1824, zengif +51,
aom-decoder-rs +16662 (real AV1 elementary streams from a retired `aom-rs`
harness, mapped by measured input format onto `fuzz_decode` / `fuzz_obu_parse`).
Crash artifacts without triage metadata and the aom animated test fixtures were
parked under `s3://zenfuzz/imported/2026-07-25-dev-32gb/` — a prefix
`triage-crashes.sh` never scans (it only syncs `crashes/*`), so nothing
auto-files from there. Full detail:
`~/work/hetzner-backup-dev-32gb/MANIFEST.md`.

## Uncommitted drift: ops `triage-crashes.sh` is AHEAD of the committed source

`~/work/zenfuzz-farm/triage-crashes.sh` differs from
`imazen/zen-workspace@origin/main:fuzz-farm/triage-crashes.sh` by ~91 lines —
edited directly in the ops dir on 2026-07-13 (there is a
`triage-crashes.sh.bak-2026-07-13` beside it) and never committed. Everything
else in the ops dir matches `origin/main` (`afcfa87`).

**Running `deploy.sh` right now would silently overwrite those improvements**,
because it extracts `origin/main` over this directory. Commit the ops copy to
`zen-workspace:fuzz-farm/` *before* the next deploy. This was left alone rather
than committed because the `zen-workspace` checkout is on a detached HEAD
(`5d2b26a`) that does not contain `fuzz-farm/`, and its working tree holds four
unrelated uncommitted files from 2026-05 belonging to another session.

## 2026-08-10 — the corpus sync was re-uploading EVERY file EVERY visit (~$1.6k/yr)

**Symptom:** Cloudflare R2 bill showing ~1M Class A operations/day.

**Measured** (Cloudflare GraphQL `r2OperationsAdaptiveGroups`, 14d to 2026-08-10):
Class A was 15.6M ops, of which **PutObject 15.35M — and `zenfuzz` alone was
10.84M (71%)**, a flat ~850-930k/day. `zenfuzz` GetObject mirrored it at
~1.2-1.4M/day. Flat-and-symmetric is the tell: not organic corpus growth, but a
fixed round-trip repeated per target visit.

**Root cause** — `fuzz_one()` does `r2_pull_corpus` → fuzz → `r2_push_corpus`:

- `r2_pull_corpus` used `s5cmd cp "s3://.../corpus/<key>/*"`, which
  unconditionally re-downloaded the whole corpus (1 Class-B GetObject/file/visit).
- Downloading stamps every local file with **mtime = now**.
- `r2_push_corpus` used bare `s5cmd sync`, whose default strategy compares
  **size AND mtime** and uploads when the source is newer. Post-pull, every local
  file is newer than its R2 object — so **the entire corpus re-uploaded every
  visit** (1 Class-A PutObject/file/visit).

At the time of diagnosis: 355k corpus files/box, 136 targets, ~5.5 visits/hour/box
(600s slice), 2 boxes fuzzing → ~900k PutObject/day. Matches the measurement.

**Fix (verified empirically before deploy):** add `--size-only` to BOTH directions.
libFuzzer names corpus entries by SHA1-of-contents, so identical name == identical
bytes == identical size; `--size-only` is an exact identity test here, not an
approximation. Controlled test on a scratch prefix — 20 seeded objects, 2 new
inputs added after a pull:

| | default sync | `--size-only` |
|---|---|---|
| push from unchanged dir | 0 | 0 |
| push from **pulled** dir (identical bytes) | **20** | 0 |
| push after adding 2 new inputs | 22 | **2** |

**Gotcha for the future:** `s5cmd sync` being "incremental" is only true when
mtimes are meaningful. Any pull-then-push loop defeats it, because the pull
resets mtimes. If a workflow round-trips through object storage, either pass
`--size-only` or never re-download what you already have.

**Deploy state:** applied to `~/work/zenfuzz-farm/fuzz-rotate.sh` (backup:
`fuzz-rotate.sh.bak-2026-08-10-115222`) and hand-installed + `systemctl restart
zen-fuzz` on both fuzzing boxes (`zen-fuzz-cx43` 78.47.81.174 x86_64,
`zen-arm-dev` 167.233.19.242 arm64) on 2026-08-10. `zen-arm-big` runs no fuzz
service. `deploy.sh` was NOT used — it extracts `zen-workspace:fuzz-farm/`, a
path that does not exist in that repo, so it would have destroyed the edit.
**This file is now the second piece of uncommitted ops drift** (see the section
above re: `triage-crashes.sh`) — commit both to `zen-workspace:fuzz-farm/` before
anyone runs `deploy.sh`.

### Post-fix residual (2026-08-10, measured over 5.4 h): known-crash re-repro, NOT corpus

Verified after deploy: **651 Put/min → 6.7 Put/min (97×)**; the pre-fix rate measured
937,787/day, matching the independent 14-day average (~900k/day). Corpus sync is fixed.

Nearly all the residual is ONE pathology. `handle_crash` uploads **3 objects per crash**
(`$art_name` — unique per input — plus `meta.json` + `repro.txt`, both overwritten), and it
does a full `cargo fuzz run` repro (120 s timeout) *before* anything knows the signature is
already filed. Suppression happens later, in workstation triage. So a target that crashes
constantly on a known bug re-uploads and re-reproduces forever:

- `crashes/aom-decoder-rs/fuzz_decode/x86_64/` holds **7,654 objects across 2 signature
  dirs**; `d7f6615546f357e4` alone has **7,337** — 7,335 distinct crashing inputs for ONE
  bug (aom-decoder-rs#11, `deblock.rs:366`), already OPEN and suppressed in triage.
- 2026-08-10: `aom-decoder-rs :: fuzz_decode` started 15:40:30Z and the next target did not
  start until 16:18:59Z — **a 38-minute run on a 600 s slice**, i.e. ~28 min of pure crash
  handling, producing the flat ~71 Put/min plateau in the R2 per-minute series (3 Puts ×
  ~660 crashes ≈ the ~1,988 observed).

**The R2 cost is the small half (~9.6k Put/day, ~$0.04/day). The real cost is fuzzing
capacity** — slices on hot targets spend most of their wall-clock re-confirming a bug filed
weeks ago. NOT fixed here: bounding it means changing crash-handling semantics, and a naive
per-slice cap could drop a genuinely-new signature hiding behind a noisy known one. Options
to weigh: cap artifacts handled per (target, slice) with a logged skip count; keep a
box-local seen-signature set to skip the repro (needs a cheap pre-repro signature); or
`-max_len`/dict tuning on the noisiest targets. Decide before "optimizing" it away.

**`zentrain` traffic is legitimate — no action needed.** It writes a steady
~2.1k PutObject/hour (~50k/day, ~5% of Class A) as a smooth drip, not bursts.
~264/hr is `refresh_snapshots.sh` (132 ledger snapshots every 30 min); the
balance is a **zenfleet worker on `lianli`** running job
`avifgen-sf-gpu-rescue-20260808` on its RTX 2080 — container
`ghcr.io/imazen/zenfleet-worker:exec-gpu-avifgen-66e3c417`. It is correctly
configured (`--ledger-in /tmp/ledger_snapshot.parquet`, reporting `snap=330495`
already-done cells skipped), so this is real work, not the re-do tax.
Worth knowing when hunting a writer: **the household LAN nodes are easy to
forget** — tower, vast, and Hetzner were all clean, and the process was on a
basement box reachable only by IP (`lianli` does not resolve via mDNS).

## 2026-08-21 — workstation migration silently killed ALL workstation crons (9 days)

**Symptom:** every farm log's last write clustered at 2026-08-12 17:00–17:21;
`crontab -l` → "no crontab for lilith"; `/var/spool/cron/crontabs/` empty.

**Root cause:** the workstation moved from the WSL2 VM to a native Ubuntu box
(`dev`, AMD 9950X3D 16c/32t, 60 GiB, kernel 7.0.0-30-generic, first boot
2026-08-20 15:50). The home directory migrated (state as of Aug 12 17:21 —
when the old box went quiet), but the crontab lives in `/var/spool/cron/`,
which is machine-local root-owned state and did NOT come along. Every
workstation cron — farm (triage-crashes 30m, sync-tree 6h, grab-arm-dev 30m)
AND non-farm (restic noon home-backup, midnight fuzz-nightly, zenavif
predictor crons, jobsys refresh_snapshots, cargo-sweep) — was silently dead
2026-08-12 → 2026-08-21.

**Fix (2026-08-21 ~00:30 MDT):** restored the crontab from
`~/tmp/fuzzbackup/crontab-new.txt` (the 2026-07-30 last-intended version, with
the temp-cred cron correctly left disabled). The backup living under `~` is
what saved us — it migrated with home. Verified `cron.service` active; ran
triage once for real (creds, s5cmd, gh auth, ledger all work on the new box).
Also restored: `cargo-sweep` binary (`cargo install`, v0.8.0 — `~/.cargo/bin`
lost it in migration) and the `mntv-gallery` user service (inactive since
boot; started, linger already enabled).

**Backlog result: ZERO new findings in 9 days.** Triage over the accumulated
R2 crashes: filed=0, regressions=0, already-known=254, build-failures-skipped=378.
Boxes never stopped fuzzing (the 2026-07-30 permanent R2 token made the dead
cred cron moot — temp creds would have expired ~Aug 16 and broken uploads).

**Farm state at check:** zen-fuzz-cx43 active+rotating (up 31d, disk 40%,
service since the 08-10 size-only deploy); zen-arm-dev zen-fuzz active;
zen-arm-xl (cax41, purpose=dev, fuzz=yes) EXISTS and runs zen-fuzz — the
grab-arm cron succeeded at some point; sync-tree/deploy now resolve 3 boxes.

**DEGRADATION, not yet fixed: ~78 of 211 target-visits/24h on cx43 are
"build failed/skipped"**, in whole-crate clusters. Two distinct causes seen:
- zenjpeg/*, zenpipe(/zencodecs)/*, ultrahdr/*, zenavif/*: `error: failed to
  select a version for the requirement zencodec = "^0.1.24"` — box-side Cargo
  resolution broken in the tree frozen at Aug 12 by the dead sync-tree.
- zentone::fuzz_curves: `Fuzz target exited with exit status: 77` (startup
  failure, not a compile error).
Re-ran sync-tree 2026-08-21 (fresh tree to all 3 boxes). **Re-check the
failing-target set after the boxes rebuild** (`journalctl -u zen-fuzz | grep
"build failed"`); if the zencodec ^0.1.24 resolution persists, debug on-box —
suspect a synced `.cargo` override/[patch] pointing at paths that are
incoherent in the synced snapshot.

**Lesson:** crontabs are machine-local state. After ANY workstation
migration/reinstall, `crontab -l` is a first-hour check, along with
`systemctl --user` services and `~/.cargo/bin` binaries. Keep the crontab
backup under `~/tmp/fuzzbackup/` current whenever the crontab changes.

**Crontab change 2026-08-21 (post-restore):** the noon `backup-restic.sh` line
was DISARMED (commented) at the user's direction — backup-system redesign is
delayed; the tentative lake direction is SeaweedFS. `crontab-new.txt` +
a dated backup in `~/tmp/fuzzbackup/` reflect the disarmed state. Do not
re-arm without user direction. All farm crons remain active.


## 2026-08-28 — stale-tree recurrences, unfilable repros, a cron that could not file

Triaging the 20 open `fuzz:` issues from this workstation (the only host with
`/mnt/v` + R2 creds + libdav1d) turned up three farm defects, all fixed in
this commit:

1. **The boxes fuzzed this workstation's checkout, not origin.** `sync-tree.sh`
   rsyncs `~/work/zen` and only overlaid `fuzz/` from origin/main. Every repo
   with a "RECURRED after <fix>" issue was 4–58 commits behind origin here
   (aom-decoder-rs 5, zenextras 6, zentone 13, zenjxl-decoder 58), so the
   boxes kept fuzzing pre-fix code and re-uploaded fixed signatures the day
   after the fix landed (aom-decoder-rs#12/#13 vs e884702/09d7028;
   zenextras#17–#20 vs 3fe603f). Replaying every artifact of those piles on
   origin/main: 5,352 + 83 inputs, 0 panics. `overlay_canonical_crates` now
   fetches and overlays each crates.list crate with its origin/main (or
   origin/master — zenrav1e never got the old fuzz/ overlay because it has no
   `main`), rsync --delete, keeping the box's .git / target / fuzz state.
2. **Unclassifiable repros were filed under their own file name.** A repro
   whose log had no panic, no sanitizer summary and no oom/leak/timeout
   artifact fell through `norm()` to the artifact name — one issue per
   artifact, forever. zenwebp#87/#88 were two `error: no bin target named
   demux_container` build logs. `norm()` now returns UNCLASSIFIED for those
   (counted + printed, never filed) and BUILD knows the extra cargo failures.
3. **This host has not filed a single issue since the 08-20 migration.**
   `gh` lives in `~/.local/share/mise/shims`, which the crons' PATH lacked, so
   every `gh issue create` failed silently (`2>/dev/null`) — 5,849 "FAILED to
   file … left for retry" lines in /tmp/fuzz-triage.log — and the ledger
   re-open check's `gh issue view` failed too. All eight scripts now put the
   mise shims on PATH. Issues filed 08-23..08-28 (zenwebp#79–#88, zentone#25/
   #26, zenjxl-decoder#55, aom-decoder-rs#12/#13, zenextras#16–#20) came from
   some other invocation whose ledger this host never saw; the ledger was
   reconciled from GitHub (466 rows appended, `filed-issues.tsv.bak-2026-08-28`
   beside it) BEFORE re-enabling filing, or the first working run would have
   re-filed all of them as duplicates.

Also: aom-decoder-rs was archived on GitHub today (superseded by zenav1-aom)
— removed from crates.list; its two open fuzz issues cannot be closed.
The ops dir had drifted ahead of this directory since 07-13 (ledger re-open
check) and 08-10 (`--size-only` corpus sync) — landed in the parent commit,
so `deploy.sh` no longer rolls them back.

**Verified live 2026-08-28 22:40 UTC:** `deploy.sh main` → cac7d5e on all three
boxes (zen-arm-dev, zen-fuzz-cx43, zen-arm-xl); first `sync-tree.sh` with the
overlay: 75 crate overlays (25 crates × 3 boxes; `zenpipe` and
`zenpipe/zencodecs` dedupe to one root), 0 `!!` lines, rc=0. Ledger:
607 rows after reconciliation. The zentone#25/#26 NaN (Bt2446B) was the one
LIVE bug in the 20 open fuzz issues; everything else was stale-tree
recurrence, a June false re-file, or an unclassifiable build log.
