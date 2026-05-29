# ARM dev box (zen-arm-dev) — Hetzner CAX21

Primary persistent ARM box for autonomous perf iteration across zen crates.
Provisioned 2026-05-28 to bypass the Oracle A1.Flex free-tier capacity-wait
lottery (a separate retry loop still races for the eventual free-tier slot;
see `ORACLE_ARM_BOX.md`). Hetzner CAX21 ships Ampere Altra Neoverse N1 — the
**same ISA family** as Oracle A1.Flex (Neoverse N1) — so any tuning derived
here transfers directly.

## Connection

- Alias: `ssh arm-zen`
- Public IPv4: `167.233.19.242`
- Public IPv6: `2a01:4f8:c014:6b48::1`
- User: `root` (Hetzner default; cloud-init also creates `ubuntu` for parity
  with the Oracle setup-arm-box.sh script which assumes `~ubuntu`)
- Key: `~/.ssh/zen-arm-dev` (ed25519, no passphrase, mode 600)
- Shape: CAX21 — 4 vCPU (Ampere Altra, Neoverse N1) + 8 GB RAM + 80 GB NVMe
- Location: `fsn1` (Falkenstein DC Park 1, Germany)
- Hetzner server ID: `133798423`
- Labels: `purpose=persistent-dev-box, owner=lilith, arch=arm64, name=zen-arm-dev`
- Cost: €0.0118/hr, **€8.46/mo monthly cap** (Hetzner billing caps cloud
  servers at one month equivalent; the box is effectively flat-rate above
  ~30 days/mo of uptime)

## Phone access (Z Fold 7 / Termux) — added 2026-05-29

Run Claude Code *on the box* from the phone, in a persistent tmux session
that survives disconnects.

- **Connect as `ubuntu`** (not root — that's where node/claude live).
- **Dedicated phone key:** `~/.ssh/zfold7-arm-zen` (local copy), authorized
  in `~ubuntu/.ssh/authorized_keys` on the box. Fingerprint
  `SHA256:7P25YztUB0HAdpUhPjOKTMz1kEF312a3UQ5aUkG+Syo`. Separate from the
  master `zen-arm-dev` key so it can be revoked independently (delete that
  one line from the box's authorized_keys).
- **Local convenience alias:** `ssh arm-zen-ubuntu` (this machine).
- **`cc` launcher** (`~ubuntu/.local/bin/cc`): `tmux new-session -A -s claude
  "claude; exec bash -l"` — attaches the persistent `claude` session or
  creates it. An `AUTO-CC` guard in `~ubuntu/.bashrc` execs `cc` on any
  interactive SSH/mosh login (skips if already in tmux or `~/.no-cc` exists —
  the admin escape hatch).
- **mosh 1.4.0** installed (`/usr/bin/mosh-server`) for resilience across
  phone sleep / wifi↔cellular. Host firewall is fully open (ufw inactive,
  empty nft/iptables). If mosh hangs at "Connecting…" but SSH works, a
  **Hetzner cloud firewall** is blocking UDP **60000–61000** — allow that
  range (`hcloud firewall ...`); SSH on 22 is the always-works fallback.
- **sshd keepalive** for flaky links: `/etc/ssh/sshd_config.d/99-mobile.conf`
  (ClientAliveInterval 30, count 6).
- **First run needs a one-time `claude` login** (OAuth, completed in the
  phone browser) — the box was not yet authenticated as of setup.

Termux first-time setup: `pkg install openssh mosh`, drop the private key at
`~/.ssh/zfold7-arm-zen` (chmod 600), add a `~/.ssh/config` Host block
(`User ubuntu`, that IdentityFile), then `mosh arm-zen` (or `ssh arm-zen`).

### Surviving Termux filesystem loss

Termux's `$HOME` (key, `~/.ssh/config`, installed packages) is wiped on
Android app-data clears / Termux reinstall. The fix: keep a self-contained
restore script on **`/sdcard`** (Android shared storage, survives the wipe).

- Canonical script: `~/work/zen/hetzner-arm-config/zen-phone-setup.sh` — it
  has the private key embedded in a heredoc, installs openssh+mosh, and writes
  `~/.ssh/{zfold7-arm-zen,config}`. Place it once at `/sdcard/zen/zen-phone-setup.sh`.
- **Recover after a wipe** (3 commands): `termux-setup-storage` →
  `bash /sdcard/zen/zen-phone-setup.sh` → `mosh arm-zen`. The persistent
  `claude` tmux session on the box is untouched, so you resume where you left off.
- Tradeoff: the key sits in cleartext on `/sdcard`, readable by apps with
  storage permission. Acceptable for a low-value dev box + independently
  revocable key; if that's a concern, either add a passphrase to the key or
  switch to Tailscale SSH (no key file on the phone at all).

## Tooling

The dev-tool fleet is **declared in TOML** at
[`~/work/zen/scripts/.mise.toml`](scripts/.mise.toml) and applied by
[mise](https://mise.jdx.dev/). The bash parity script
[`scripts/setup-arm-box.sh`](scripts/setup-arm-box.sh) is now a thin
3-layer wrapper:

1. APT system libs + dev headers (root, apt) — clang/lld/cmake/mold/valgrind/...
2. `.mise.toml` toolchain + CLI fleet (ubuntu, mise) — rust/node/python +
   jj/just/samply/ripgrep/fd/bat/fzf/hyperfine + the full cargo-subcommand
   fleet + mdbook/wasm-tools/gh/oxipng. See the TOML for the canonical list.
3. Out-of-mise extras — dssim/butteraugli-cli/git-delta
   (`cargo install` from source; no published prebuilts),
   Node-LTS+Claude Code CLI (nvm/npm), hcloud/s5cmd/rclone
   (vendor installers).

### First-time setup on a fresh box

```sh
scp ~/work/zen/scripts/.mise.toml arm-zen:zen-mise.toml        # → /home/ubuntu/zen-mise.toml
ssh arm-zen 'sudo -u ubuntu bash -s' < ~/work/zen/scripts/install_mise.sh
# Or full layered setup (apt + mise + extras):
ssh arm-zen 'sudo -u ubuntu bash -s' < ~/work/zen/scripts/setup-arm-box.sh
```

### Re-applying after `.mise.toml` edits

```sh
rsync -a ~/work/zen/scripts/.mise.toml \
  arm-zen:/home/ubuntu/.config/mise/config.toml
ssh arm-zen 'sudo -u ubuntu mise install --yes --jobs 4'
```

### GitHub rate-limit avoidance (mandatory for bulk install)

mise queries the GitHub API for release tags. Unauthenticated quota is
**60 req/hr** — burned in <1 min by a full `mise install`. Set
`GITHUB_TOKEN` on the box's mise env so future runs use the
**5000 req/hr** authenticated quota:

```sh
GHTOKEN=$(gh auth token)
TMP=$(mktemp); chmod 600 "$TMP"
printf '[env]\nGITHUB_TOKEN = "%s"\n' "$GHTOKEN" > "$TMP"
scp -q "$TMP" arm-zen:/tmp/env.toml
ssh arm-zen 'sudo install -o ubuntu -g ubuntu -m 600 \
  /tmp/env.toml /home/ubuntu/.config/mise/env.toml && sudo rm /tmp/env.toml'
rm "$TMP"
```

`~/.config/mise/env.toml` is auto-merged into the environment of every
`mise` invocation. Mode-600, owned by ubuntu — not world-readable.
Already done for `zen-arm-dev` on 2026-05-28.

### Confirmed installed (2026-05-28 first run, pre-mise)

Manual + nvm install path used during initial provisioning:
- `rustc 1.96.0`, `cargo 1.96.0` (stable + nightly), aarch64/x86/wasm targets
- `cargo-asm`, `cargo-watch`, `cargo-expand`, `cargo-llvm-lines`,
  `cargo-binstall`, `cargo-nextest`, `cargo-llvm-cov`, `cargo-deny`
- `dssim`, `butteraugli-cli`, `delta 0.19.2`
- `gh 2.93.0`, `hyperfine 1.18.0`
- `hcloud 1.65.0`, `s5cmd v2.3.0`, `rclone v1.74.2`
- `node v24.16.0`, `claude 2.1.154`

After `mise install` lands (with `GITHUB_TOKEN`):
- `jj`, `just`, `samply`, `ripgrep`, `fd`, `bat`, `fzf`, `mdbook`,
  `wasm-tools`, `oxipng`, the full `cargo-*` subcommand set

### Lessons from the initial provisioning (2026-05-28)

- Mass binstalls hit GitHub rate limit fast — always set
  `GITHUB_TOKEN` on the box before bulk install.
- `cargo-flamegraph` no longer publishes prebuilts; the `.mise.toml`
  registers `cargo:inferno` for flamegraph rendering instead.
- `nvm use --lts` blows up under `set -u`
  (`PROVIDED_VERSION: unbound variable`); setup-arm-box.sh now wraps
  nvm in `set +u/-u`.
- s5cmd release URL pattern is `s5cmd_<ver>_Linux-arm64.tar.gz`
  (not the `latest/download/s5cmd_Linux-arm64.tar.gz` pattern the old
  script used); fixed in setup-arm-box.sh.

## Operational

- **Persistent** — do NOT terminate unless replacing. Contrast with the
  zenmetrics fleet sweep boxes which are ephemeral by design.
- Status: `hcloud server list --label purpose=persistent-dev-box`
- Describe: `hcloud server describe zen-arm-dev`
- Reboot: `hcloud server reboot zen-arm-dev`
- Resize up (if benches need more cores):
  `hcloud server change-type zen-arm-dev cax31` (then `cax41`).
- Destroy (only if replacing):
  `hcloud server delete zen-arm-dev`

## Cloud-init

Canonical config: `~/work/zen/hetzner-arm-config/cloud-init.yaml`.
Adapted from the Oracle variant (`~/work/zen/oracle-arm-config/`) — the
two differences are:

1. Hetzner Ubuntu 24.04 default login is `root`; the config explicitly
   creates a `ubuntu` user so the parity script (which `su - ubuntu`s
   everywhere) works without modification.
2. Includes the `chage -d 99999 -E -1 -I -1 -M -1 root || true; passwd
   -u root 2>/dev/null || true` PAM password-aging fix (also applied to
   ubuntu). Hetzner Ubuntu has the same bug as Oracle Ubuntu — without
   the fix, SSH-key-only logins lock out after ~1 day with "password
   expired."

Bootstrap-done marker: `/var/lib/zen-arm-bootstrap-done` (touched at end
of runcmd).

## Provisioning audit trail

- Setup log: `/tmp/hetzner_arm_dev_setup_2026-05-28.log` (volatile — tee'd
  during initial provision; nothing further written to /tmp)
- Parity-setup log: `/tmp/arm_parity_<timestamp>.log`
- SSH key fingerprint: `SHA256:AmhpJJVzyMH3IM/N3RbBxVVNLw+8AG5pcRndxLZsw/o`
- Hetzner SSH-key ID (uploaded pubkey): `112978404`
- Cloud-init: `~/work/zen/hetzner-arm-config/cloud-init.yaml`

## Alternative — Oracle A1.Flex (always-free)

`ORACLE_ARM_BOX.md` documents the parallel always-free Oracle path. The
capacity-retry loop runs in the background; if a free-tier slot ever
lands and you want to consolidate to $0, kill this CAX21 and use the
Oracle box. Both run the same parity script + cloud-init shape, so the
swap is a config-file edit + an SSH alias re-point.

## Autonomous iteration pattern

Spawn an agent with a brief like:

> SSH to `arm-zen`, clone `~/work/zen/<crate>` from the local checkout
> via rsync OR `git clone` from origin, run `cargo bench` (zenbench),
> capture results to `~/work/zen-arm-bench/<date>/<crate>.tsv`, diff
> against the local x86 baseline at `~/work/zen-x86-bench-latest/...`,
> identify regressions or opportunities, propose+test a fix, commit on
> a branch + push. Always rsync the final results back to local
> `~/work/zen-arm-results/<sweep-id>/`.

Parallels the Oracle box's pattern verbatim — same ISA, same parity
tooling, only the SSH alias and host IP differ.

## Cost control

- Hetzner CAX21 monthly cap: **€8.46/mo** (≈ $9.20/mo).
- Hourly burn: **€0.0118/hr** (€0.28/day if always-on).
- Resize to CAX31 (8 vCPU + 16 GB) caps at €15.13/mo if needed.
- Killing the box: `hcloud server delete zen-arm-dev`. Persistent storage
  doesn't survive; rsync results back to local before delete.
- Hetzner billing is granular; deleting partway through the month bills
  only the hours used (no full-month minimum below the cap).
