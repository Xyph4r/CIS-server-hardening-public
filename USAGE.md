# Usage: from a fresh server to fully hardened

A straight-through walkthrough of the whole lifecycle covered by this repo.
Replace the angle-bracket placeholders (`<os_group>`, `<ip>`, etc.) with real
values. Run everything from the `ansible/` directory unless a step says
otherwise.

## 0. One-time control-node setup

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cp inventory/hosts.example.ini inventory/hosts.ini      # gitignored - real hosts go here
```

## 1. Add the server to inventory

Edit `inventory/hosts.ini`:

- Add the host under the right OS group: `rocky9`, `rocky10`, `centos10`,
  `debian12`, `debian13`, `ubuntu22`, or `ubuntu26`.
- Set `ansible_host=<ip>` if the hostname doesn't already resolve.
- Make sure that group is **also** listed under `[cis_servers:children]` —
  if it's missing, `ssh_access`/`netbird`/`fail2ban` silently skip the host
  while OS-specific hardening still runs, which is easy to miss.

## 2. Bootstrap: root+password → a real admin account with your SSH key

A freshly-delivered box only has root+password. This is a one-time,
separate step — **not** a full `site.yml` run — because the full run
disables root login and password auth entirely.

```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags ssh_access \
  --limit <os_group> -e ansible_user=root --ask-pass
```

First-ever connection to this host? Trust its key by IP (Ansible connects
via `ansible_host`, so a `known_hosts` entry from connecting by hostname
won't cover it):

```bash
ssh -o UserKnownHostsFile=~/.ssh/known_hosts root@<ip> exit
```

Verify the new admin account actually works before going any further:

```bash
ssh <cis_admin_username>@<host_or_ip>      # username set in group_vars/all.yml
sudo -v
```

## 3. Switch to the new admin account for every run after this

Edit `inventory/hosts.ini`: change `ansible_user=root` to
`ansible_user=<cis_admin_username>` under `[cis_servers:vars]` (or per-group).

## 4. Dry run — review the diff before touching anything for real

```bash
ansible-playbook -i inventory/hosts.ini site.yml --limit <os_group> --check --diff
```

## 5. Apply CIS hardening

Disables root SSH login and password auth, locks down the firewall, enables
auditd/AIDE/rsyslog, hardens sshd/sudo/PAM, sets file/mount permissions, etc.
Also configures unattended security updates here (`auto_updates_enabled`
defaults to `true` — no separate step needed, unlike netbird/fail2ban/wazuh
below, which are all opt-in). Keep this SSH session open until step 5b
passes — don't disconnect blind on a misconfigured box.

```bash
ansible-playbook -i inventory/hosts.ini site.yml --limit <os_group>
```

From a **new** terminal, confirm the hardening actually took effect:

```bash
ssh <cis_admin_username>@<host_or_ip>       # should still work, key-only
ssh root@<host_or_ip>                       # should now be refused
```

## 6. (Optional) OpenSCAP compliance scan — evidence, before/after comparison

```bash
cd ../scap
ansible-playbook -i ../ansible/inventory/hosts.ini playbooks/scap_scan.yml --limit <os_group>
cd ../ansible
```

Reports land in `reports/<hostname>/` (gitignored).

For ongoing drift detection (not just a one-off before/after), use the
scan-only wrapper instead — same scan, but meant to be re-run periodically
(manually, or wired into your own crontab — see the script's own output for
an example; no dedicated always-on control node is assumed here):

```bash
../ci/recurring-scap-scan.sh <os_group>
```

## 7. (Optional) Join the private Netbird network

Get a setup key from your Netbird dashboard (self-hosted or SaaS) first.

```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags netbird --limit <os_group> \
  -e "netbird_enabled=true netbird_setup_key=<setup-key>"
```

`--tags netbird` runs in isolation, so the firewall's "trust the `wt0`
interface" rule hasn't been applied yet — follow up with the firewall
section (or a full run). `netbird_enabled=true` has to be passed again here;
Ansible vars don't persist between separate invocations, so without it this
silently skips the trust-rule task instead of applying it:

```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags cis_3.4,cis_3.5 \
  --limit <os_group> -e netbird_enabled=true
```

Verify `wt0` actually landed in the firewall's trusted zone/equivalent, not
just that the interface exists:

- firewalld (Rocky/CentOS): `firewall-cmd --get-active-zones`
- nftables (Debian): `nft list ruleset | grep -A2 -B2 wt0`
- ufw (Ubuntu): `ufw status | grep wt0`

```bash
ssh <cis_admin_username>@<host_or_ip> "netbird status -d"
```

## 8. (Optional) fail2ban — bans a source IP after repeated SSH auth failures

Add your own IP(s)/CIDR to `fail2ban_ignoreip` in `group_vars/all.yml`
first — a burst of your own failed connections can otherwise ban you
(`bantime` is short by default specifically so that's not catastrophic if
it happens).

```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags fail2ban --limit <os_group> \
  -e "fail2ban_enabled=true"
```

## 9. (Optional, placeholder-driven) Wazuh agent

Only usable once you have a real Wazuh manager running — fill in
`wazuh_manager_address` in `group_vars/all.yml` first (not secret, safe to
commit), then:

```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags wazuh_agent --limit <os_group> \
  -e "wazuh_agent_enabled=true wazuh_agent_registration_password=<pw>"
```

Verify against Wazuh's current install docs before relying on this — see
`TODO.md`, "ACTION NEEDED - Wazuh agent role is placeholder-only".

## 10. Add application firewall rules (a web server, an API, etc.)

Edit `inventory/group_vars/<os_group>.yml`, add the port(s):

```yaml
<os_group>cis_extra_allowed_tcp_ports: [80, 443]
```

Then apply just the firewall section:

```bash
ansible-playbook -i inventory/hosts.ini site.yml --tags cis_3.4 --limit <os_group>
```

## 11. Reboot to finish activating /tmp hardening

`/dev/shm` hardening (`nodev,nosuid,noexec`) applies immediately during
step 5; `/tmp` (via systemd `tmp.mount`) only takes effect after a reboot —
a live remount would hide `/tmp`'s current contents from anything with an
open file handle there, which is riskier than waiting for a planned reboot.

```bash
ssh <cis_admin_username>@<host_or_ip> "sudo reboot"
```

## 12. Re-running later (config drift, new controls, routine compliance)

```bash
ansible-playbook -i inventory/hosts.ini site.yml --limit <os_group> --check --diff  # review first
ansible-playbook -i inventory/hosts.ini site.yml --limit <os_group>                 # apply
cd ../scap && ansible-playbook -i ../ansible/inventory/hosts.ini playbooks/scap_scan.yml --limit <os_group>
```
