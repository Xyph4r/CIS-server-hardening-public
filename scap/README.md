# OpenSCAP / scap-security-guide - assessment layer

Scans servers against the CIS profile shipped in `scap-security-guide` and
produces evidence (HTML report + XCCDF `results.xml`) you can hand to an
auditor or feed back into the Ansible remediation roles.

## Playbooks

| Playbook                  | Does |
|----------------------------|------|
| `playbooks/scap_scan.yml`       | Installs OpenSCAP, scans, fetches report + results.xml |
| `playbooks/scap_remediate.yml`  | Scans, then generates (but does **not** apply) an Ansible fix playbook from the failed rules, fetched for human review |

Reports land under `../reports/<hostname>/` (gitignored - these are
per-host compliance evidence, not source).

## Profile IDs and datastream filenames

`scap-security-guide` renames its datastream XML file and occasionally its
profile IDs between releases. The defaults set per-OS in
`ansible/inventory/group_vars/{rocky,debian,ubuntu}.yml`
(`scap_datastream_candidates`, `scap_profile_id`) are current as of recent
SSG releases, but **verify on a real target before trusting them**:

```bash
# list datastream files actually installed
ls /usr/share/xml/scap/ssg/content/

# list every profile a given datastream offers
oscap info /usr/share/xml/scap/ssg/content/ssg-<file>-ds.xml
```

Rocky Linux: recent `scap-security-guide` ships a `rocky-linux9` product
build; older versions only have RHEL9 content, which is compatible with
Rocky (same upstream). The candidate list tries `ssg-rocky-linux9-ds.xml`
first and falls back to `ssg-rhel9-ds.xml`.

Ubuntu's SSG content splits CIS into separate Level 1/2 x Server/Workstation
profiles (`..._cis_level1_server`, `..._cis_level2_server`, ...) rather than
one combined `cis` profile like RHEL/Debian - the default here is
`xccdf_org.ssgproject.content_profile_cis_level1_server`.

## Why remediation isn't auto-applied

`oscap xccdf generate fix --fix-type ansible` produces a working Ansible
playbook straight from the benchmark's fix content, but it's generated
blind - it doesn't know your SSH access model, your firewall exceptions, or
that a given "failed" rule is an accepted risk. `scap_remediate.yml` fetches
it to `reports/<host>/remediation-*.yml` for review rather than running it.
The intended loop is:

1. `scap_scan.yml` - see where you stand.
2. Compare failures against `ansible/roles/<os>_cis/` - most should already
   be covered; gaps mean the role needs an equivalent task added (tracked in
   `../mappings/`).
3. Run the relevant `ansible/site.yml` role.
4. `scap_scan.yml` again to verify and produce the evidence artifact.

Use the SCAP-generated fix content as a reference/diff against your Ansible
role, not as something you run directly against production.
