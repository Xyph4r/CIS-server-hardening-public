# Usage: from a fresh server to fully hardened

One straight-through walkthrough of the whole lifecycle covered by this repo.
Replace the angle-bracket placeholders; comments mark each stage. Run
everything from the `ansible/` directory unless a step says otherwise.

```bash
# ============================================================================
# 0. One-time control-node setup
# ============================================================================
cd ansible
ansible-galaxy collection install -r requirements.yml
cp inventory/hosts.example.ini inventory/hosts.ini      # gitignored - real hosts go here

# ============================================================================
# 1. Add the server to inventory
# ============================================================================
# Edit inventory/hosts.ini:
#   - add the host under the right OS group: rocky9, rocky10, centos10,
#     debian12, debian13, ubuntu22, or ubuntu26
#   - set ansible_host=<ip> if the hostname doesn't already resolve
#   - make sure that group is ALSO listed under [cis_servers:children] -
#     if it's missing, ssh_access/netbird/fail2ban silently skip the host
#     while OS-specific hardening still runs, which is easy to miss

# ============================================================================
# 2. Bootstrap: root+password -> a real admin account with your SSH key
# ============================================================================
# A freshly-delivered box only has root+password. This is a one-time,
# separate step - NOT a full site.yml run - because the full run disables
# root login and password auth entirely.
ansible-playbook -i inventory/hosts.ini site.yml --tags ssh_access \
  --limit <os_group> -e ansible_user=root --ask-pass

# First-ever connection to this host? Trust its key by IP (Ansible connects
# via ansible_host, so a known_hosts entry from connecting by hostname
# won't cover it):
ssh -o UserKnownHostsFile=~/.ssh/known_hosts root@<ip> exit

# Verify the new admin account actually works BEFORE going any further:
ssh <cis_admin_username>@<host_or_ip>      # username set in group_vars/all.yml
sudo -v

# ============================================================================
# 3. Switch to the new admin account for every run after this
# ============================================================================
# Edit inventory/hosts.ini: change ansible_user=root to
# ansible_user=<cis_admin_username> under [cis_servers:vars] (or per-group).

# ============================================================================
# 4. Dry run - review the diff before touching anything for real
# ============================================================================
ansible-playbook -i inventory/hosts.ini site.yml --limit <os_group> --check --diff

# ============================================================================
# 5. Apply CIS hardening
# ============================================================================
# Disables root SSH login + password auth, locks down the firewall, enables
# auditd/AIDE/rsyslog, hardens sshd/sudo/PAM, sets file/mount permissions,
# etc. Keep this SSH session open until step 5b passes - don't disconnect
# blind on a misconfigured box.
ansible-playbook -i inventory/hosts.ini site.yml --limit <os_group>

# 5b. From a NEW terminal - confirm the hardening actually took effect:
ssh <cis_admin_username>@<host_or_ip>       # should still work, key-only
ssh root@<host_or_ip>                       # should now be refused

# ============================================================================
# 6. (Optional) OpenSCAP compliance scan - evidence, before/after comparison
# ============================================================================
cd ../scap
ansible-playbook -i ../ansible/inventory/hosts.ini playbooks/scap_scan.yml --limit <os_group>
# Reports land in reports/<hostname>/ (gitignored)
cd ../ansible

# ============================================================================
# 7. (Optional) Join the private Netbird network
# ============================================================================
# Get a setup key from your Netbird dashboard (self-hosted or SaaS) first.
ansible-playbook -i inventory/hosts.ini site.yml --tags netbird --limit <os_group> \
  -e "netbird_enabled=true netbird_setup_key=<setup-key>"

# --tags netbird runs in isolation, so the firewall's "trust the wt0
# interface" rule hasn't been applied yet - follow up with the firewall
# section (or a full run):
ansible-playbook -i inventory/hosts.ini site.yml --tags cis_3.4,cis_3.5 --limit <os_group>

# Verify:
ssh <cis_admin_username>@<host_or_ip> "netbird status -d"

# ============================================================================
# 8. (Optional) fail2ban - bans a source IP after repeated SSH auth failures
# ============================================================================
# Add your own IP(s)/CIDR to fail2ban_ignoreip in group_vars/all.yml first -
# a burst of your own failed connections can otherwise ban you (bantime is
# short by default specifically so that's not catastrophic if it happens).
ansible-playbook -i inventory/hosts.ini site.yml --tags fail2ban --limit <os_group> \
  -e "fail2ban_enabled=true"

# ============================================================================
# 9. Add application firewall rules (a web server, an API, etc.)
# ============================================================================
# Edit inventory/group_vars/<os_group>.yml, add the port(s):
#   <os_group>cis_extra_allowed_tcp_ports: [80, 443]
# Then apply just the firewall section:
ansible-playbook -i inventory/hosts.ini site.yml --tags cis_3.4 --limit <os_group>

# ============================================================================
# 10. Reboot to finish activating /tmp hardening
# ============================================================================
# /dev/shm hardening (nodev,nosuid,noexec) applies immediately during step 5;
# /tmp (via systemd tmp.mount) only takes effect after a reboot - a live
# remount would hide /tmp's current contents from anything with an open file
# handle there, which is riskier than waiting for a planned reboot.
ssh <cis_admin_username>@<host_or_ip> "sudo reboot"

# ============================================================================
# 11. Re-running later (config drift, new controls, routine compliance)
# ============================================================================
ansible-playbook -i inventory/hosts.ini site.yml --limit <os_group> --check --diff  # review first
ansible-playbook -i inventory/hosts.ini site.yml --limit <os_group>                 # apply
cd ../scap && ansible-playbook -i ../ansible/inventory/hosts.ini playbooks/scap_scan.yml --limit <os_group>
```
