# CIS Server Hardening Automation

Ansible-based CIS Benchmark hardening for Linux servers, paired with
OpenSCAP + `scap-security-guide` for compliance scanning and verification.

## Scope

Server (not workstation/desktop) hardening for:

| OS               | Role              | CIS Benchmark reference               |
|-------------------|-------------------|--------------------------------------|
| Rocky Linux 9     | `rocky9_cis`      | CIS Rocky Linux 9 Benchmark v2.0.0   |
| Debian 12         | `debian12_cis`    | CIS Debian Linux 12 Benchmark        |
| Ubuntu 22.04 LTS  | `ubuntu22_cis`    | CIS Ubuntu Linux 22.04 LTS Benchmark |

Other versions (Rocky 8/10, Debian 11, Ubuntu 24.04, ...) can be added the
same way — copy the closest role, rename, and adjust deltas. The official
CIS Benchmark PDFs are kept outside this repo (not automated content, and
CIS's license terms don't clearly permit redistribution) — see `TODO.md`.

## Repository layout

```
ansible/            Hardening playbooks + roles (the remediation side)
  roles/
    rocky9_cis/
    debian12_cis/
    ubuntu22_cis/
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

## Quick start

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cp inventory/hosts.example.ini inventory/hosts.ini   # edit with real hosts
ansible-playbook -i inventory/hosts.ini site.yml --check --diff   # dry run first
ansible-playbook -i inventory/hosts.ini site.yml
```

```bash
cd scap
ansible-playbook -i ../ansible/inventory/hosts.ini playbooks/scap_scan.yml
```

Always run `--check --diff` against a non-production host or snapshot first.
Some controls (SSH access hardening, sudo `use_pty`, PAM lockout thresholds)
can lock you out of a misconfigured box if applied blind.

## Requirements

- Ansible-core >= 2.15 on the control node
- SSH access + a privilege-escalation-capable account on targets
- Target OS: Rocky Linux 9, Debian 12, or Ubuntu 22.04 (server installs)
- `scap-security-guide` + `openscap-scanner` (the `openscap_scan` role
  installs these on the target automatically)
