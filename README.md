# CIS Server Hardening Automation

Ansible-based CIS Benchmark hardening for Linux servers, paired with
OpenSCAP + `scap-security-guide` for compliance scanning and verification.

See `USAGE.md` for a single, straight-through command walkthrough covering
the whole lifecycle - bootstrap, hardening, OpenSCAP, Netbird, fail2ban,
custom firewall rules, through to a fully hardened box.

## Scope

Server (not workstation/desktop) hardening for:

| OS               | Role              | CIS Benchmark reference               |
|-------------------|-------------------|--------------------------------------|
| Rocky Linux 9     | `rocky9_cis`      | CIS Rocky Linux 9 Benchmark v2.0.0   |
| Rocky Linux 10    | `rocky10_cis`     | CIS Rocky Linux 10 Benchmark (provisional — see `TODO.md`) |
| CentOS Stream 10  | `centos10_cis`    | CIS CentOS Stream 10 Benchmark (provisional — see `TODO.md`) |
| Debian 12         | `debian12_cis`    | CIS Debian Linux 12 Benchmark        |
| Debian 13         | `debian13_cis`    | CIS Debian Linux 13 Benchmark (provisional — see `TODO.md`) |
| Ubuntu 22.04 LTS  | `ubuntu22_cis`    | CIS Ubuntu Linux 22.04 LTS Benchmark |
| Ubuntu 26.04 LTS  | `ubuntu26_cis`    | CIS Ubuntu Linux 26.04 LTS Benchmark (provisional — see `TODO.md`) |

Other versions (Rocky 8, Debian 11, ...) can be added the same way — copy
the closest role, rename, and adjust deltas. The official CIS Benchmark PDFs
are kept outside this repo (not automated content, and CIS's license terms
don't clearly permit redistribution) — see `TODO.md`.

Five roles run outside the per-OS `*_cis` roles, against every host:

- **`ssh_access`** — creates the admin account (`cis_admin_username`, default
  `ops`) and deploys the team's SSH public keys (`cis_authorized_keys`) to
  it. Runs *first* in `site.yml`, before any role that might disable
  password authentication. Does **not** handle the very first connection to
  a freshly-delivered box, which is still root+password — see "Bootstrapping
  a new server" below.
- **`fail2ban`** — opt-in (`fail2ban_enabled: false` by default) SSH
  brute-force ban. Not a CIS control, an operational add-on — see
  "fail2ban" below.
- **`netbird`** — opt-in (`netbird_enabled: false` by default) install/join
  for a private Netbird mesh network. See "Private networking" below.
- **`unattended_upgrades`** — **on by default** (`auto_updates_enabled: true`),
  unlike the others. Security-only automatic patching (`dnf-automatic` /
  `unattended-upgrades`) plus an automatic reboot when an applied update
  actually requires one, at a fixed daily time. See "Unattended security
  updates" below.
- **`wazuh_agent`** — opt-in and placeholder-driven
  (`wazuh_agent_enabled: false`, `wazuh_manager_address` is a placeholder
  string). Installs the Wazuh agent and points it at your manager once you
  fill in real values. See "Wazuh agent" below.

## Repository layout

```
ansible/            Hardening playbooks + roles (the remediation side)
  roles/
    ssh_access/      admin user + key deployment, runs before everything else
    rocky9_cis/
    rocky10_cis/
    centos10_cis/
    debian12_cis/
    debian13_cis/
    ubuntu22_cis/
    ubuntu26_cis/
    fail2ban/         opt-in SSH brute-force ban
    netbird/          opt-in private-network join
    unattended_upgrades/  on by default, security-only auto-patching
    wazuh_agent/          opt-in, placeholder-driven
scap/                OpenSCAP scanning + SCAP-generated remediation (the assessment side)
  roles/openscap_scan/
  playbooks/
mappings/            CIS control -> Ansible task -> SCAP rule cross-reference
ci/                  scan -> remediate -> re-scan pipeline glue, plus a
                     scan-only script for periodic drift checks
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

## Bootstrapping a new server (e.g. a fresh VPS)

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
ssh -i ~/.ssh/<your-key> ops@<host>   # then `sudo -v`

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

## fail2ban — optional, not a CIS control

Bans a source IP after repeated SSH auth failures. Off by default
(`fail2ban_enabled: false`). Worth having given the constant background
noise of bots hitting any public IP on port 22, but genuinely optional:
`PasswordAuthentication no` already makes brute-forcing this box futile on
its own — fail2ban just cuts the log noise and connection churn.

**No static public IP (common for home/office connections)?** Don't put a
public address in `fail2ban_ignoreip` — it goes stale the next time your ISP
reassigns you one, and silently stops protecting you. Best fix: once
Netbird is joined, use its stable overlay CIDR instead (`ip -4 addr show
wt0` on the box; verify the actual range, don't assume):

```yaml
# group_vars/all.yml
fail2ban_enabled: true
fail2ban_ignoreip:
  - "100.64.0.0/10"   # Netbird's overlay range - verify against the real interface
```

Before Netbird is up, `fail2ban_maxretry` already defaults to 10 (higher
than fail2ban's usual 5) specifically because there's no IP exemption
available yet for most setups — a few genuine retries of your own (wrong
key offered first, a bad Ansible run reconnecting) shouldn't tip it over. A
dynamic-DNS hostname also works in `fail2ban_ignoreip` if you want
IP-based protection sooner (fail2ban resolves hostnames there at jail
start/reload — stale between reloads, but better than nothing).

Bans are non-permanent (`fail2ban_bantime: 1h` by default) specifically so a
self-ban isn't catastrophic — it expires on its own. The firewall action
used to actually block traffic (`fail2ban_banaction`) is set per-OS in
`group_vars/<os>.yml` to match that role's firewall backend
(firewalld/nftables/iptables-under-ufw) — verify it against
`ls /etc/fail2ban/action.d/` on the real box before fully trusting it, same
caveat as everything else version-dependent in this repo.

```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags fail2ban
```

## Unattended security updates — on by default, not a CIS-numbered control

Security-only automatic patching: `dnf-automatic` on Rocky/CentOS,
`unattended-upgrades` on Debian/Ubuntu. Unlike `fail2ban`/`netbird`, this
defaults **on** (`auto_updates_enabled: true`) — patching cadence matters as
much as initial hardening, and a security-only (not "everything") policy
keeps the risk of an update breaking something reasonably low.

Also reboots automatically when an applied update actually needs one (e.g.
a new kernel) — `auto_updates_reboot: true` by default, at a fixed daily
time (`auto_updates_reboot_time`, default `03:00`) rather than immediately,
so it never reboots mid-task. On Debian/Ubuntu this uses
`unattended-upgrades`' own native scheduled-reboot feature; on
Rocky/CentOS (which has no equivalent built in) it's a small systemd timer
that checks `needs-restarting -r` before rebooting, pinned to run an hour
after the (also-pinned, non-randomized) update timer.

Set `auto_updates_enabled: false` per-host/group for any box that needs
manual change control instead, or `auto_updates_reboot: false` to apply
updates but never reboot automatically:

```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags auto_updates
```

## Wazuh agent — opt-in, placeholder-driven

Installs the Wazuh agent via Wazuh's official repo and points it at your
manager through the `WAZUH_MANAGER` environment variable (Wazuh's own
documented scripted-install method — the package's postinstall script
populates `ossec.conf` itself, so this repo doesn't need to hand-maintain
that config's schema).

Off by default and the manager address is a literal placeholder
(`wazuh_manager_address: "CHANGE_ME.wazuh-manager.example"`) until you've
actually got a Wazuh manager running. Once you do:

```yaml
# group_vars/all.yml - address is not secret, safe to commit
wazuh_manager_address: "wazuh.example.com"   # or an internal/Netbird-only address
```

```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags wazuh_agent \
  -e "wazuh_agent_enabled=true wazuh_agent_registration_password=<pw>"
```

The agent only needs outbound connectivity (ports 1514/1515 by default),
which every `*_cis` role's firewall already allows — no inbound rule
changes needed for the agent side. If/when you expose the manager's own
dashboard/API, route that through `cis_vpn_only_tcp_ports` rather than
publicly — that was the original motivating case for that variable.

**Verify before relying on this**: repo URLs, GPG key location, and package
naming in `ansible/roles/wazuh_agent/tasks/main.yml` are accurate as of
when this was written, but Wazuh versions/URLs do change — cross-check
against [Wazuh's current installation docs](https://documentation.wazuh.com)
once you're ready to deploy agents for real, same caveat as every other
externally-sourced install step in this repo.

## Private networking (Netbird) — scaffolding, not full architecture

The overall network architecture (what's public, what's VPN-only, where
Wazuh/other services actually live) is future work and out of scope here.
What's in place now so that work isn't blocked later:

- `ansible/roles/netbird/` installs the Netbird client and joins it to your
  mesh, entirely opt-in (`netbird_enabled: true` + `netbird_setup_key` passed
  via `--extra-vars`/vault, never committed). SSO login (browser-based,
  interactive) also works — run `netbird up` by hand once — but obviously
  can't be driven by Ansible; the role's setup-key flow is for unattended
  joins only.
- **`cis_vpn_trust_interface: true` (default)** — every `*_cis` role's
  firewall config trusts *all* traffic arriving on the Netbird interface
  (firewalld "trusted" zone / nftables blanket `iifname` accept / `ufw allow
  in on <iface>`). This is what makes basic things like `ping`/SSH over the
  mesh actually work — without it, the interface exists but sits in
  whatever the OS's default firewall zone is, which blocks everything not
  explicitly allowed. Set `false` if you'd rather not trust the whole
  interface and only expose specific ports via `cis_vpn_only_tcp_ports`
  below.
- `cis_vpn_only_tcp_ports` (`group_vars/all.yml`) — for the narrower case:
  any TCP port listed there is opened **only** on the Netbird interface,
  never on the public interface, useful if you want `cis_vpn_trust_interface:
  false` but still need one specific service reachable over the mesh.

**Ordering matters here**: `site.yml` runs the Netbird play *before* the
`*_cis` hardening plays specifically so the `wt0` interface already exists
by the time the firewall-trust tasks run — on a full run this is automatic.
If you use `--tags netbird` in isolation to join a host for the first time,
follow up with a full run (or `--tags cis_3.4,cis_3.5`) so the firewall
trust rule actually gets applied. **`netbird_enabled=true` has to be passed
again on that follow-up command too** — Ansible variables don't persist
between separate `ansible-playbook` invocations, so without it the
`when: netbird_enabled | bool and ...` guard on the trust-rule task
correctly (and silently) evaluates false and skips:
```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags cis_3.4,cis_3.5 \
  --limit <os_group> -e netbird_enabled=true
```

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
- Target OS: Rocky Linux 9/10, CentOS Stream 10, Debian 12/13, Ubuntu 22.04, or Ubuntu 26.04 (server installs)
- `scap-security-guide` + `openscap-scanner` (the `openscap_scan` role
  installs these on the target automatically)
