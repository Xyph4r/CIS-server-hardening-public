# TODO / before you trust this against real servers

## First-run checklist

- `cd ansible && ansible-galaxy collection install -r requirements.yml`
- Copy `inventory/hosts.example.ini` -> `inventory/hosts.ini` and fill in
  real targets (gitignored, won't get committed).
- Dry run before anything else:
  `ansible-playbook -i inventory/hosts.ini site.yml --check --diff`
- Only then: `ansible-playbook -i inventory/hosts.ini site.yml`

## Watch out for

- **SSH hardening tasks** in every role's `tasks/section5_access_authentication.yml`
  are the ones most likely to lock you out if a variable is wrong
  (`cis_ssh_permit_root_login`, `cis_ssh_allowed_groups`, etc. in
  `inventory/group_vars/`). Keep an out-of-band console session open the
  first time you apply for real, not just SSH.
- **OpenSCAP datastream/profile IDs drift between `scap-security-guide`
  releases.** Before trusting the defaults in
  `inventory/group_vars/{rocky,debian,ubuntu}.yml`
  (`scap_datastream_candidates`, `scap_profile_id`), run on a real target:
  ```
  ls /usr/share/xml/scap/ssg/content/
  oscap info /usr/share/xml/scap/ssg/content/<file>
  ```
- No `ansible-core` / `ansible-lint` available in the environment this was
  authored in — only a plain YAML syntax check was run. Do a real
  `ansible-playbook --syntax-check` before the first live run.

## Known gaps

- Coverage is a Level 1 Server foundation, not the full ~200-400 controls
  per CIS benchmark. See `mappings/README.md` for how to track what's
  covered vs outstanding, and diff against
  [Ansible-Lockdown](https://github.com/ansible-lockdown) for exhaustive
  per-OS content.
- `mappings/*.csv` files don't exist yet — need to be generated from a real
  OpenSCAP scan per OS (see `mappings/README.md`).
- Bootloader password (CIS ~1.4) is deliberately left off by default
  (`*cis_set_bootloader_password: false`) since it breaks unattended
  PXE/kickstart re-provisioning in most fleets — decide per environment.
