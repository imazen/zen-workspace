# Oracle ARM dev box (zen-arm-dev)

Persistent OCI A1.Flex (Ampere ARM Neoverse N1) dev box for autonomous
ARM perf iteration across the zen workspace. Free-tier, $0/mo.

## Status (as of 2026-05-28)

**PENDING CAPACITY** — VCN + subnet + IGW + security list + SSH key + cloud-init
are all provisioned and ready. Instance launch is **blocked by Oracle free-tier
A1.Flex capacity exhaustion** across all 3 us-ashburn-1 ADs (a famously
persistent issue — Oracle's free-tier ARM is heavily oversubscribed). A
persistent retry loop is running in the background that races other free-tier
users for the next freed slot.

Once the loop succeeds, run **`oci-arm-finalize.sh`** to populate this doc
with the live IP + verify the box. Until then, the SSH alias `oracle-arm-zen`
points to `HostName PENDING-OCI-CAPACITY` and will fail loudly.

## Connection

- Alias: `ssh oracle-arm-zen`
- Public IP: `PENDING-CAPACITY`
- Instance OCID: `PENDING-CAPACITY`
- User: `ubuntu`
- Key: `~/.ssh/oci-zen-arm` (ed25519, no passphrase, mode 600)
- Shape: VM.Standard.A1.Flex (target 4 OCPU + 24 GB Ampere ARM Neoverse N1)
- Region, AD: us-ashburn-1 (any of AD-1, AD-2, AD-3 — whichever the loop catches)
- Free tier: always-free ($0/mo at 4 OCPU + 24 GB; degrades to 2/12 or 1/6 if 4/24 stays denied)

## Network resources (provisioned 2026-05-28)

- VCN: `ocid1.vcn.oc1.iad.amaaaaaayvj4hpqaoccoeklhbafit5dbqwst7kyvw7ae22rv3zankfcsfdua`
  (display: `zen-arm-vcn`, CIDR 10.0.0.0/16)
- Internet Gateway: `ocid1.internetgateway.oc1.iad.aaaaaaaa2j7jtpf74ex5ihznncvc25t7s7zynrblqolt7u4h5vwyzincykfq`
- Default route table: 0.0.0.0/0 → IGW
- Default security list: ingress 22/tcp, ICMP type 3 (path-MTU); egress all
- Subnet: `ocid1.subnet.oc1.iad.aaaaaaaa4dmayrowdzv3jpwyxiwazc6a4rgug5dbvgixjxt74abbbwny72ga`
  (display: `zen-arm-subnet`, CIDR 10.0.1.0/24, regional, public IP enabled)

## Image

- `Canonical-Ubuntu-24.04-aarch64-2026.04.30-1`
- OCID: `ocid1.image.oc1.iad.aaaaaaaaioyy7je3vndsccly24frkfptl5lggvyupubg74awcf2gmua7k3ra`

## Capacity-retry tooling

Three artifacts coordinate the eventual launch:

- **`~/bin/oci-arm-launch-retry.sh`** — bash retry loop. Sweeps 3 ADs × 3 sizes
  (4/24, 2/12, 1/6 OCPU/GB) every ~60 s. Writes status to `/tmp/oci_arm_retry.log`.
  On success, writes the full instance JSON to `/tmp/oci_arm_success.json` and exits 0.
- **`~/.config/systemd/user/oci-arm-retry.service`** — systemd user unit wrapping
  the above. Currently NOT enabled (the loop is running via `nohup setsid` from
  the original session). To enable across reboots:
  `systemctl --user enable --now oci-arm-retry.service`.
- **`~/bin/oci-arm-finalize.sh`** — post-success hook. Reads
  `/tmp/oci_arm_success.json`, extracts public IP, updates `~/.ssh/config`,
  scans the host key, verifies aarch64 + cloud-init status + tooling, and
  patches this doc with the live IP.

### How to check status

```sh
tail -20 /tmp/oci_arm_retry.log         # most recent sweep results
ls -la /tmp/oci_arm_success.json        # if exists → loop succeeded
ps aux | grep oci-arm-launch-retry      # confirm loop alive
```

### Post-success

```sh
/home/lilith/bin/oci-arm-finalize.sh    # populates SSH config, verifies, updates this doc
ssh oracle-arm-zen 'uname -m'           # should print "aarch64"
```

## Pre-installed (via cloud-init)

Per `/tmp/oci_zen_arm_cloud_init.yaml` (canonical at this path; same content
embedded in the user_data of every launch attempt):

- **System**: build-essential, clang, lld, cmake, pkg-config, git, gh
  (via apt repo), curl, wget, unzip, vim, tmux, htop, jq, rsync, awscli,
  hyperfine, linux-tools-generic, libssl-dev, libpq-dev, ca-certificates,
  gnupg, python3 + venv + pip
- **Rust**: stable + nightly (minimal profile), rustfmt, clippy
- **Cargo helpers**: cargo-watch, cargo-expand, cargo-asm, cargo-llvm-lines
  (best-effort; cloud-init does not fail if one is offline)
- **Profile**: `RUSTFLAGS="-C target-cpu=neoverse-n1"` and
  `CARGO_TARGET_DIR=$HOME/work/.cargo-target` set in `/etc/profile.d/zen.sh`
- **Workspace skeleton**: `$HOME/work/zen/` (empty; clone per task)
- **Bootstrap marker**: `/var/lib/zen-arm-bootstrap-done` (touched at the
  end of runcmd; check this to know cloud-init runcmd finished)

## Autonomous iteration pattern

Spawn an agent with a brief like:

> SSH to `oracle-arm-zen`, clone `~/work/zen/<crate>` from the local
> checkout via rsync OR `git clone` from origin, run `cargo bench`
> (zenbench), capture results to `~/work/zen-arm-bench/<date>/<crate>.tsv`,
> diff against the local x86 baseline at `~/work/zen-x86-bench-latest/...`,
> identify regressions or opportunities, propose+test a fix, commit on a
> branch + push. Always rsync the final results back to local
> `~/work/zen-arm-results/<sweep-id>/`.

## Cost control

- Box runs continuously at $0 (always-free A1.Flex up to 4 OCPU + 24 GB total
  per tenancy).
- If you ever exceed 4 OCPU + 24 GB across all A1 instances in the tenancy,
  Oracle starts billing. Verify quota: `oci limits resource-availability get`.
- Kill the box (if needed):
  `oci compute instance terminate --instance-id <ocid> --force`.
- **Do NOT terminate** as part of normal use. This is meant to be persistent —
  contrast with Salad/Hetzner sweeps which always tear down.

## Provisioning audit trail

- Setup log: `/tmp/oracle_arm_setup_2026-05-28.log`
- Retry loop log: `/tmp/oci_arm_retry.log` (append-only; survives reboot? — no,
  /tmp is volatile per the project policy, so check `journalctl --user -u
  oci-arm-retry` once the systemd unit is enabled).
- Cloud-init user_data: `~/work/zen/oracle-arm-config/cloud-init.yaml`
  (canonical, persistent location). A copy was also written to
  `/tmp/oci_zen_arm_cloud_init.yaml` during the initial setup; that's
  volatile per the project policy. The retry script reads the persistent path.

## Known constraint

Oracle's free-tier A1.Flex in us-ashburn-1 has been **capacity-exhausted
across all 3 ADs at all sizes (1/6, 2/12, 4/24) at the time of provisioning**
(2026-05-28T23:55Z, ~3-minute sweep). The retry loop handles this — capacity
opens up unpredictably as other free-tier users churn. Expect anywhere from
minutes to days before a slot lands.
