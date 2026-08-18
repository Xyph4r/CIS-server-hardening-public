# CIS Server Hardening Automation

Ansible-based CIS Benchmark hardening for Linux servers, paired with
OpenSCAP + `scap-security-guide` for compliance scanning and verification.

## Scope

Server (not workstation/desktop) hardening for:

| OS               | Role              | CIS Benchmark reference               |
|-------------------|-------------------|--------------------------------------|
| Rocky Linux 9     | `rocky9_cis`      | CIS Rocky Linux 9 Benchmark v2.0.0   |
| Rocky Linux 10    | `rocky10_cis`     | CIS Rocky Linux 10 Benchmark (provisional — see `TODO.md`) |
| Debian 12         | `debian12_cis`    | CIS Debian Linux 12 Benchmark        |
| Ubuntu 22.04 LTS  | `ubuntu22_cis`    | CIS Ubuntu Linux 22.04 LTS Benchmark |
| Ubuntu 26.04 LTS  | `ubuntu26_cis`    | CIS Ubuntu Linux 26.04 LTS Benchmark (provisional — see `TODO.md`) |

Other versions (Rocky 8, Debian 11, ...) can be added the same way — copy
the closest role, rename, and adjust deltas. The official CIS Benchmark PDFs
are kept outside this repo (not automated content, and CIS's license terms
don't clearly permit redistribution) — see `TODO.md`.

Two roles run outside the per-OS `*_cis` roles, against every host:

- **`ssh_access`** — creates the admin account (`cis_admin_username`, default
  `ops`) and deploys the team's SSH public keys (`cis_authorized_keys`) to
  it. Runs *first* in `site.yml`, before any role that might disable
  password authentication. Does **not** handle the very first connection to
  a freshly-delivered box, which is still root+password — see "Bootstrapping
  a new server" below.
- **`netbird`** — opt-in (`netbird_enabled: false` by default) install/join
  for a private Netbird mesh network. See "Private networking" below.

## Repository layout

```
ansible/            Hardening playbooks + roles (the remediation side)
  roles/
    ssh_access/      admin user + key deployment, runs before everything else
    rocky9_cis/
    rocky10_cis/
    debian12_cis/
    ubuntu22_cis/
    ubuntu26_cis/
    netbird/          opt-in private-network join
scap/                OpenSCAP scanning + SCAP-generated remediation (the assessment side)
  roles/openscap_scan/
  playbooks/
mappings/            CIS control -> Ansible task -> SCAP rule cross-reference
ci/                  scan -> remediate -> re-scan pipeline glue
```

One repo, not several — see rationale in `mappings/README.md`. Assessment
(OpenSCAP) and remediation (Ansible) are versioned together deliberately so a
benchmark bump never lets one drift out of sync with the other.

## How the pieces fit together

1. **Scan** a host against the relevant CIS profile with OpenSCAP
   (`scap/playbooks/scap_scan.yml`) to get a baseline / evidence report.
2. **Remediate** with the matching Ansible role
   (`ansible/roles/<os>_cis/`).
3. **Re-scan** to verify and produce the compliance evidence artifact.

`ci/scan-remediate-rescan.sh` runs all three steps in sequence for a given
inventory group and drops timestamped reports under `reports/` (gitignored).

## Coverage note — read before relying on this for an audit

Each role ships a real, working **Level 1 Server** subset covering the major
CIS sections (initial setup / filesystem & MAC, services, network, logging &
auditing, access & authentication, and system file permissions). A full CIS
Benchmark is 200-400+ individual controls per OS; this is a solid foundation
to build on, not a claim of 100% control coverage out of the box. Treat the
official CIS Benchmark PDF for each OS as the source of truth and extend the
section task files control-by-control — each task is tagged with its CIS control ID
(e.g. `cis_5.2.10`) to make gaps easy to find and to allow selective runs
via `--tags`/`--skip-tags`. `mappings/` is where you track what's actually
covered vs outstanding.

For exhaustive, continuously-maintained control coverage, the
[Ansible-Lockdown](https://github.com/ansible-lockdown) project (per-OS
`*-CIS` roles) and RedHat/ComplianceAsCode's `scap-security-guide` remediation
content are the standard references worth diffing against.

## Bootstrapping a new server (e.g. a fresh Hetzner box)

A newly-delivered box only has `root` + a password, not a key and not the
`ops` account this repo expects. That first connection is a one-time,
separate step — `ssh_access` creates the real admin account, it doesn't
handle getting in as root:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cp inventory/hosts.example.ini inventory/hosts.ini   # edit with real hosts

# 1. One-time bootstrap as root (password auth, not yet trusted with a key)
ansible-playbook -i inventory/hosts.ini site.yml --tags ssh_access \
  --limit rocky10 -e ansible_user=root --ask-pass

# 2. Confirm the new account works BEFORE going further
ssh -i ~/.ssh/keys/xtc3br4@yk-prim ops@<host>   # then `sudo -v`

# 3. Switch ansible_user in hosts.ini from root to ops (cis_servers:vars),
#    then run everything else normally
ansible-playbook -i inventory/hosts.ini site.yml --check --diff   # dry run first
ansible-playbook -i inventory/hosts.ini site.yml
```

Doing this in two passes (create+verify the account, *then* run the roles
that disable root login / password auth) means a broken step 1 never leaves
you locked out with no way back in.

```bash
cd scap
ansible-playbook -i ../ansible/inventory/hosts.ini playbooks/scap_scan.yml
```

Always run `--check --diff` against a non-production host or snapshot first.
Some controls (SSH access hardening, sudo `use_pty`, PAM lockout thresholds)
can lock you out of a misconfigured box if applied blind.

## Private networking (Netbird) — scaffolding, not full architecture

The overall network architecture (what's public, what's VPN-only, where
Wazuh/other services actually live) is future work and out of scope here.
What's in place now so that work isn't blocked later:

- `ansible/roles/netbird/` installs the Netbird client and joins it to your
  mesh, entirely opt-in (`netbird_enabled: true` + `netbird_setup_key` passed
  via `--extra-vars`/vault, never committed).
- Every `*_cis` role's firewall config understands `cis_vpn_only_tcp_ports`
  (`group_vars/all.yml`) — any TCP port listed there is opened **only** on
  the Netbird interface (`cis_vpn_interface`, default `wt0`), never on the
  public interface, regardless of firewall backend (firewalld zone /
  nftables `iifname` match / `ufw allow in on <iface>`).

So the intended pattern once you deploy something like Wazuh: don't expose
its dashboard/API port publicly at all — add it to `cis_vpn_only_tcp_ports`
instead, and it's only reachable over the Netbird mesh. SSH itself stays
publicly reachable by default (needed to bootstrap Netbird in the first
place); moving SSH itself behind Netbird-only is a reasonable next step once
the mesh is proven out, but isn't wired up automatically here since it can
lock you out if Netbird isn't actually connected yet.

## Requirements

- Ansible-core >= 2.15 on the control node
- SSH access + a privilege-escalation-capable account on targets
- Target OS: Rocky Linux 9/10, Debian 12, Ubuntu 22.04, or Ubuntu 26.04 (server installs)
- `scap-security-guide` + `openscap-scanner` (the `openscap_scan` role
  installs these on the target automatically)
