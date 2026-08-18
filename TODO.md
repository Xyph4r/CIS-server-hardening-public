# TODO / before you trust this against real servers

## Findings from the first live run (hermes-nue, Rocky 10)

Full run against a real box, end to end: bootstrap → hardening → verified
`PermitRootLogin no` / `PasswordAuthentication no` actually reject root
(client offers a password, server refuses, disconnects after `MaxAuthTries`)
while `xyph4r-adm` key-only access keeps working. What came up along the way:

- **FIXED** - `content: 'Defaults logfile="/var/log/sudo.log"\n'` used
  single-quoted YAML, so `\n` was written as two literal characters instead
  of a real newline, breaking `visudo -cf` validation and failing task 5.2
  on every OS role (same copy-pasted line in all five). Now a `content: |`
  block scalar in all five roles.
- **FIXED** - `ansible_distribution`/`ansible_os_family`/etc. used bare
  throughout every role triggered `INJECT_FACTS_AS_VARS` deprecation
  warnings on ansible-core 2.21+. Swapped to `ansible_facts['distribution']`
  etc. everywhere (`ssh_access` + all five `*_cis` roles).
- **FIXED (cosmetic)** - task 1.2.2 warned `Unable to find '/etc/yum.repos.d'`
  via `with_fileglob`'s silent-skip-with-warning behavior. Now gated behind
  an explicit `stat` check instead - same effective behavior, no warning.
- **STILL OPEN** - *why* `/etc/yum.repos.d` didn't exist on the live Rocky 10
  box in the first place is unconfirmed - repo file layout may have moved in
  Rocky/RHEL 10. Next login, check
  `ls /etc/yum.repos.d /etc/dnf/repos.d 2>/dev/null` and report back so 1.2.2
  can point at the real path - until then, GPG-check enforcement for repo
  files is a no-op on Rocky 10.
- **STILL OPEN (accepted, not a bug)** - `--check --diff` fails partway
  through section 3 (`firewalld` service task): package installs are
  simulated in check mode, so a following "manage this package's service"
  task fails because the unit genuinely isn't there yet. Real (non-check)
  runs aren't affected.

## Manual setup checklist (do these before running site.yml for real)

1. **Bootstrap connectivity (root+password boxes, e.g. Hetzner).** A fresh
   box only has root+password - no key, no `ops` account yet. That first
   connection is a separate, one-time step, NOT a full `site.yml` run:
   ```
   ansible-playbook -i inventory/hosts.ini site.yml --tags ssh_access \
     --limit <group-or-host> -e ansible_user=root --ask-pass
   ```
   This creates `cis_admin_username` (default `ops`) and deploys your keys
   to it - see README "Bootstrapping a new server". Verify
   `ssh ops@<host>` + `sudo -v` work BEFORE running the rest of `site.yml`,
   which will disable root SSH login and password auth entirely.
2. **`hosts.ini`** - copy from `inventory/hosts.example.ini`, fill in real
   hosts under `[rocky9]` / `[rocky10]` / `[debian12]` / `[ubuntu22]` /
   `[ubuntu26]`. Set `ansible_user=root` only for the one-time bootstrap
   step above, then switch it to `ops` (or whatever `cis_admin_username` is)
   for every run after.
3. **SSH keys** - `group_vars/all.yml` already lists both
   `xtc3br4-yk-prim` and `xtc3br4-yk-sec` public keys under
   `cis_authorized_keys`, deployed to `cis_admin_username` by the
   `ssh_access` role. Nothing to do here unless you want a different admin
   username - set `cis_admin_username` in `group_vars/all.yml` (one value,
   shared across all hosts as written; override per-OS group_vars if it
   needs to differ per host).
4. **Confirm before password auth gets disabled.** `cis_ssh_password_auth`
   defaults to `"no"` (see `group_vars/all.yml`) - since `ssh_access` runs
   before the hardening roles in the same playbook run, this should be safe,
   but run `--check --diff` first and keep a console/out-of-band session
   open the first time regardless.
5. **App ports.** Default firewall policy is deny-by-default + SSH only.
   Anything you actually run (a web app, Wazuh, etc.) needs its port added
   to `*cis_extra_allowed_tcp_ports` (public) or `cis_vpn_only_tcp_ports`
   (Netbird-only) in group_vars - otherwise you'll harden the box and then
   can't reach your own service.
6. **Netbird, if using it.** Get a setup key from your Netbird
   management server (self-hosted or cloud), then run:
   `ansible-playbook -i inventory/hosts.ini site.yml --tags netbird --extra-vars "netbird_enabled=true netbird_setup_key=<key>"`
   (or store the key in an `ansible-vault`-encrypted file instead of
   `--extra-vars` on the command line, which ends up in shell history).
   Don't set `netbird_enabled: true` as a permanent default in group_vars
   until the setup key is actually managed somewhere safe.
7. Dry run before anything else:
   `ansible-playbook -i inventory/hosts.ini site.yml --check --diff`
   Only then: `ansible-playbook -i inventory/hosts.ini site.yml`

## Watch out for

- **SSH hardening tasks** in every role's `tasks/section5_access_authentication.yml`
  are the ones most likely to lock you out if a variable is wrong
  (`cis_ssh_permit_root_login`, `cis_ssh_password_auth`,
  `cis_ssh_allowed_groups`, etc. in `inventory/group_vars/`). Keep an
  out-of-band console session open the first time you apply for real, not
  just SSH.
- **OpenSCAP datastream/profile IDs drift between `scap-security-guide`
  releases.** Before trusting the defaults in
  `inventory/group_vars/{rocky9,rocky10,debian12,ubuntu22,ubuntu26}.yml`
  (`scap_datastream_candidates`, `scap_profile_id`), run on a real target:
  ```
  ls /usr/share/xml/scap/ssg/content/
  oscap info /usr/share/xml/scap/ssg/content/<file>
  ```
- **Ubuntu 26.04 and Rocky 10 roles are provisional.** Both cloned from
  their previous-version role (`ubuntu22_cis`, `rocky9_cis`) on the
  assumption package/service names haven't changed - reasonable, but
  unverified against a real box or an official CIS benchmark for either
  (which may not even be published yet - CIS benchmarks typically lag OS
  release by months). Their `scap_datastream_candidates` fall back to the
  previous version's SSG content for the same reason. Verify both before
  relying on them, especially Rocky 10 since a real host is already in
  `hosts.ini`.
- **`cis_admin_username` is created with NO password (locked) by design** -
  key-only account. This is why `cis_admin_passwordless_sudo` defaults to
  `true`: a locked account has no password sudo could check, so pairing a
  locked account with password-required sudo would make `sudo` permanently
  fail (this was actually broken this way briefly during development - fixed
  by flipping the default and adding `cis_admin_password_hash` as an opt-in
  escape hatch for a real console/rescue password, sourced from vault, never
  committed).
- **Netbird install method uses `pkgs.netbird.io/install.sh`** (their
  documented quick-install script, fetched via `get_url` + `command` rather
  than a hand-rolled repo definition). If Netbird changes their install flow,
  this breaks loudly (task fails) rather than silently - update
  `ansible/roles/netbird/tasks/main.yml` against current
  https://docs.netbird.io instructions if so.
- No `ansible-core` / `ansible-lint` available in the environment this was
  authored in — only a plain YAML syntax check was run. Do a real
  `ansible-playbook --syntax-check` before the first live run.

## Known gaps

- **Coverage is much smaller than "Level 1 Server foundation" might sound
  like.** Checked against the actual `OS/CIS_Rocky_Linux_10_Benchmark_v1.0.0.pdf`
  (1077 pages; the Recommendations section alone is ~1038 pages; the
  Appendix Summary Table spans ~23 pages, roughly 350-450 individual
  checklist items across Level 1/2 x Server/Workstation): `rocky10_cis`
  currently implements **61 tasks total**. Confirmed-missing just from
  spot-checking section 1.1: all filesystem *partition* hardening (separate
  partitions + nodev/nosuid/noexec for /tmp, /dev/shm, /home, /var,
  /var/tmp, /var/log, /var/log/audit - 28 checks, skipped because it's
  genuinely risky to automate on a live disk) and 3 more disabled kernel
  modules (overlay, firewire-core, usb-storage) beyond the 7 currently
  covered. Assume every other role has comparable gaps until checked.
  Treat `mappings/*.csv` as the way to actually track this per control,
  section by section, against each OS's real PDF - that's real, standalone
  work, not something to hand-wave as "mostly done."
  See `mappings/README.md` for the process, and diff against
  [Ansible-Lockdown](https://github.com/ansible-lockdown) for exhaustive
  per-OS content.
- `mappings/*.csv` files don't exist yet — need to be generated from a real
  OpenSCAP scan per OS (see `mappings/README.md`).
- Bootloader password (CIS ~1.4) is deliberately left off by default
  (`*cis_set_bootloader_password: false`) since it breaks unattended
  PXE/kickstart re-provisioning in most fleets — decide per environment.
