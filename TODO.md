# TODO / before you trust this against real servers

## Full repo audit (Rocky9/10 diff, bug sweep, doc accuracy)

- **Rocky 9 vs Rocky 10: confirmed functionally identical** apart from
  version numbers and the provisional-role comment - normalized diff shows
  no divergence, so every fix applied to one was correctly applied to both.
- **FIXED - defensive `| bool` sweep, repo-wide.** The `netbird_enabled`
  strict-boolean bug (ansible-core 2.21 rejecting a CLI string `"true"` for
  a bare `when:`) was fixed for the vars actually documented as
  `-e`-overridable, but every OTHER role-default boolean
  (`*_enforce_selinux`, `*_enforce_apparmor`, `*_configure_aide`,
  `*_configure_firewalld`, `*_configure_ufw`, `*_configure_nftables`) was
  left with the same latent bug - just not yet hit because nobody's
  overridden them via `-e`. Added `| bool` to all ~93 remaining instances
  across all 7 `*_cis` roles (both bare `when: <var>` lines and compound
  `when: <var> and ...` lines in the 3.5 Netbird-firewall blocks). Zero
  behavior change - `| bool` is a no-op on values already native booleans.
- **FIXED - docs never told you to re-pass `netbird_enabled=true` on the
  firewall-trust follow-up run.** Both README.md and USAGE.md's Netbird
  section gave `--tags cis_3.4,cis_3.5 --limit <group>` as the follow-up
  command with no `-e netbird_enabled=true` - since Ansible vars don't
  persist between separate invocations, that command silently skips the
  trust-rule task (exactly what happened live on `panoptes-flk`/centos10).
  Both docs now include the flag and a comment explaining why it's needed.
- **FIXED** - `TODO.md`'s OpenSCAP datastream verification list was missing
  `debian13`/`centos10` (added after that note was written).
- Confirmed clean (no regressions) repo-wide: `with_fileglob`,
  `include_tasks`, the single-quote `\n` sudo-logfile bug, bare
  `ansible_distribution`/`ansible_os_family` facts - all zero hits,
  including in `scap/roles/openscap_scan` and `netbird`/`fail2ban`/
  `ssh_access`, which hadn't been explicitly re-checked since their
  original fixes.
- Structural check: all 7 `*_cis` roles have identical file layout (10 yml
  files: meta/defaults/handlers/tasks-main + 6 section files), all 6
  sections wired into each role's `tasks/main.yml`, all 7 OS groups present
  and consistent across `hosts.example.ini`, `[cis_servers:children]`, and
  `site.yml`'s per-OS plays. group_vars files all carry the same required
  keys (`cis_firewall_service`, `cis_mac_type`, `cis_disable_filesystems`,
  `cis_time_sync_service`, `scap_datastream_candidates`, `scap_profile_id`,
  `fail2ban_banaction`).

## FIXED (properly, this time) - the `/etc/yum.repos.d` warning wasn't actually gone

Earlier "fix" for task 1.2.2 (Rocky 9/10) added a `stat` check + `when:` guard
so the repo-GPG-check task would *skip* cleanly instead of taking the wrong
action when `/etc/yum.repos.d` doesn't exist. That part worked. What it
didn't do: stop the warning itself (`Unable to find '/etc/yum.repos.d' in
expected paths`) from still printing on every run - confirmed reproducing on
the new `centos10_cis` role. Root cause: `with_fileglob` resolves its lookup
during task pre-processing, *before* Ansible ever evaluates the task's
`when:` - so the glob against a nonexistent directory happens (and warns)
regardless of whether the task goes on to skip. Properly fixed by moving the
conditional inside the lookup itself: `loop: "{{ query('ansible.builtin.fileglob',
'/etc/yum.repos.d/*.repo') if <flag>.stat.exists else [] }}"` - the `query()`
call only executes when the ternary's true-branch is taken, so the lookup
plugin never runs against a path that doesn't exist. Applied to all three
affected roles: `rocky9_cis`, `rocky10_cis`, `centos10_cis`.

## FIXED - granular `--tags cis_X.Y` selection never actually worked, in any role

Every `tasks/main.yml` pulled in each section file via
`ansible.builtin.include_tasks`, tagged only with the coarse section tag
(`tags: [cis_1, section1]` etc.). `include_tasks` is **dynamic** - Ansible
decides whether to step into it using only the tags on the include
statement itself, since it can't look inside a dynamic include before
deciding to run it. Any finer tag inside the file (`cis_1.1.2`, `cis_5.2`,
...) was invisible to `--tags` unless the coarse section tag also matched.
Caught when `--tags cis_1.1.2` silently ran nothing at all (not even
unrelated tasks in that file) despite the tag existing on the intended task.

This means only whole-section tags (`cis_1`...`cis_6`), `netbird`/`fail2ban`/
`ssh_access` (their own dedicated plays), or untagged full runs ever
actually worked as documented. Every more specific `--tags cis_X.Y.Z`
example anywhere in this repo's history (including several given during
live troubleshooting sessions) silently did nothing.

**Fixed** by switching every `ansible.builtin.include_tasks` to
`ansible.builtin.import_tasks` across all six `*_cis` roles' `tasks/main.yml`.
`import_tasks` is resolved statically at parse time, so `--tags` can see and
match on the real inner task tags. Coarse section tags still work exactly
as before (they're still applied to the import statement, which merges onto
every task inside) - this only fixes the granular case. One minor behavior
change: `when:` on the import line now gets ANDed onto every task inside
individually rather than skipping the whole include as one unit, so a
disabled section now shows one "skipping" line per task instead of one -
cosmetic only, no functional difference.

**Not yet re-verified**: re-run a `--tags cis_X.Y`-style selective command
against a real host to confirm this actually fixes it end-to-end (the
in-repo YAML validation only confirms the files still parse, not that
Ansible's live tag-resolution behaves as expected).

## Findings from the second live run (aragon-hel, Debian 13)

- **FIXED** - the `netbird` role's install task ran the downloaded installer
  directly (`ansible.builtin.command: /tmp/netbird-install.sh`), which failed
  with `Errno 8: Exec format error`. Root cause: the script served from
  `pkgs.netbird.io/install.sh` (physk/netbird-installer) has no shebang
  line - it's a real, valid 483-line script, just meant to be invoked via a
  shell (`bash script.sh`), not exec'd directly. Fixed by changing the task
  to `ansible.builtin.command: bash /tmp/netbird-install.sh`. This is exactly
  the "Netbird changes their install flow" risk already flagged in this
  role's comments - it broke loudly (task failure) rather than silently,
  which is what that note was hoping for.
- **FIXED** - every boolean opt-in flag (`netbird_enabled`, `fail2ban_enabled`,
  `cis_create_admin_user`, `cis_manage_authorized_keys`,
  `cis_netbird_expose_udp_port`, `cis_vpn_trust_interface`) was referenced
  bare in `when:` clauses (e.g. `when: netbird_enabled`). This is exactly how
  every doc in this repo tells you to set them via
  `-e "netbird_enabled=true ..."` - and that's precisely the case that broke:
  ansible-core 2.21's stricter conditional typing rejects the CLI's string
  `"true"` being auto-coerced to boolean for a bare `when:`, failing with
  "Conditionals must have a boolean result." Native YAML `true`/`false` in
  group_vars files was never affected - only the documented `-e` override
  path. Fixed by adding `| bool` after every one of these vars wherever used
  in a `when:` (8 files: `netbird`, `ssh_access`, `fail2ban` roles, and the
  section3_network.yml in all four firewalld/ufw *_cis roles). `| bool` is a
  safe no-op on values that are already native booleans, so this doesn't
  change behavior for YAML-set values - it only fixes the CLI-string case.
- **Inventory gotcha (not a repo bug, but easy to hit again):** a new
  `[<os>]` group added to `hosts.ini` must ALSO be added under
  `[cis_servers:children]`, or `ssh_access`/`netbird`/`fail2ban` (which all
  target `hosts: cis_servers`) silently skip that host with "no hosts
  matched" while the OS-specific hardening play (which targets the group
  directly) works fine - easy to miss since nothing errors, it just quietly
  never creates the admin user. Bit us adding `debian13`/aragon-hel.
- **SSH host-key gotcha:** Ansible keys host-key trust to whatever string is
  used to connect - if `ansible_host=<ip>` is set (as it is for every host in
  `hosts.ini`), Ansible connects by IP, so a known_hosts entry populated by
  manually SSHing to the *hostname* doesn't cover it. `rocky10`/hermes-nue
  happened to work first-try only because an earlier unrelated manual
  `ssh root@<ip>` had already populated the IP-keyed entry. For any new host,
  trust the IP directly: `ssh -o UserKnownHostsFile=~/.ssh/known_hosts root@<ip> exit`.

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
- **FIXED** - joined Netbird manually on hermes-nue (SSO login, since that
  flow needs an interactive browser and can't go through the unattended
  `netbird up --setup-key` the role uses) and `ping`ing the peer's overlay
  IP from the VPS timed out completely. Root cause: two compounding bugs.
  (1) The firewalld/nftables/ufw "trust the Netbird interface" logic in
  every `*_cis` role was gated behind `cis_vpn_only_tcp_ports | length > 0`,
  which defaults empty, so it never ran for basic connectivity (ping/SSH
  over the mesh) at all - only for the narrower "expose one specific app
  port via VPN" case. (2) Even when populated, that logic lived in a play
  that runs BEFORE the Netbird play in `site.yml`, so the `wt0` interface
  wouldn't exist yet when the firewall task tried to reference it. Fixed by:
  adding a new `cis_vpn_trust_interface: true` default that unconditionally
  trusts the whole interface (firewalld "trusted" zone / nftables blanket
  `iifname` accept / `ufw allow in on wt0`) whenever `netbird_enabled` is
  true, decoupled from `cis_vpn_only_tcp_ports`; reordering `site.yml` so
  the Netbird play runs before every `*_cis` play; and guarding every
  interface-referencing firewall task with
  `cis_vpn_interface in ansible_facts['interfaces']` so a host where the
  interface genuinely doesn't exist yet fails to a clean skip instead of an
  error. Also fixed the netbird role's "no setup key" warning to not fire
  when the interface already exists (i.e. someone joined manually via SSO,
  same as happened here) - re-run the full playbook against hermes-nue to
  apply the firewall-trust rule via code instead of the manual
  `firewall-cmd --zone=trusted --change-interface=wt0` used to unblock in
  the moment.
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
  `inventory/group_vars/{rocky9,rocky10,centos10,debian12,debian13,ubuntu22,ubuntu26}.yml`
  (`scap_datastream_candidates`, `scap_profile_id`), run on a real target:
  ```
  ls /usr/share/xml/scap/ssg/content/
  oscap info /usr/share/xml/scap/ssg/content/<file>
  ```
- **Ubuntu 26.04, Rocky 10, Debian 13, and CentOS Stream 10 roles are all
  provisional.** Each cloned from the closest existing role
  (`ubuntu22_cis`, `rocky9_cis`, `debian12_cis`, and `centos10_cis` from
  `rocky10_cis` specifically, since both are RHEL10-based and share the same
  dnf/firewalld/SELinux/chrony/AIDE tooling) on the assumption
  package/service names haven't changed - reasonable, but unverified against
  a real box or an official CIS benchmark for any of them (which may not
  even be published yet - CIS benchmarks typically lag OS release by
  months; CentOS Stream also isn't guaranteed to get its own CIS benchmark
  at all rather than relying on RHEL's). Their `scap_datastream_candidates`
  fall back to the closest RHEL/previous-version SSG content for the same
  reason. Verify all four before relying on them, especially Rocky 10 since
  a real host is already in `hosts.ini`.
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
  currently implements **61 tasks total** (now +8 for /tmp and /dev/shm
  hardening, see below). Confirmed-missing just from spot-checking section
  1.1: filesystem partition hardening for /home, /var, /var/tmp, /var/log,
  /var/log/audit (separate partitions + nodev/nosuid/noexec - ~24 checks,
  still skipped, genuinely risky to automate repartitioning a live disk with
  existing data) and 3 more disabled kernel modules (overlay, firewire-core,
  usb-storage) beyond the 7 currently covered. Assume every other role has
  comparable gaps until checked.
  - **UPDATE:** /tmp and /dev/shm (the two most commonly checked of the
    filesystem-partition controls) ARE now implemented, added across all six
    `*_cis` roles - see `cis_harden_tmp_partition`/`cis_harden_dev_shm` in
    `group_vars/all.yml`. /tmp uses systemd's built-in `tmp.mount` unit
    (hardened tmpfs) rather than resizing a real partition, sidestepping the
    live-repartitioning risk - but this means it only takes effect after a
    reboot, not immediately. /dev/shm is already tmpfs everywhere and gets
    remounted immediately with the same options.
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
