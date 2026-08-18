# Control mappings

Cross-reference between a CIS control ID, the Ansible task that implements
it, and the SCAP rule that verifies it. This is what keeps the assessment
(`scap/`) and remediation (`ansible/`) layers honest as the benchmark or the
roles change - it's also the fastest way to see what's actually covered
versus outstanding, which is why this lives in the same repo as both
(see the root README's "one repo, not several" note).

Keep one file per OS: `rocky9.csv`, `debian12.csv`, `ubuntu22.csv`.
Suggested columns:

```
cis_id,title,level,ansible_tag,scap_rule_id,status,notes
1.1.1.1,Ensure cramfs kernel module is not available,1,cis_1.1,xccdf_org.ssgproject.rule_kernel_module_cramfs_disabled,covered,
5.2.7,Ensure sudo log file exists,1,cis_5.2,xccdf_org.ssgproject.rule_sudo_custom_logfile,covered,
...,,,,,,gap - not yet implemented in ansible role
```

## How to populate this

1. Run `scap/playbooks/scap_scan.yml` against a representative host per OS.
2. Open the fetched `report-*.html` (or grep `results-*.xml` for `result="fail"`).
3. For every CIS control, note whether `ansible/roles/<os>_cis/` already has
   a matching tagged task (`ansible-playbook ... --list-tasks --tags cis_X.Y`
   is the fast way to check) and record the SCAP rule ID that verifies it.
4. Anything unmapped is a real gap - either accept the risk explicitly
   (`status: accepted-risk`, with a reason) or add the control to the
   relevant `section*.yml` task file.

This file intentionally ships empty rather than pre-filled: the accurate
version of this mapping can only be produced by scanning a real host against
the exact scap-security-guide version you have installed (rule IDs and
profile contents drift between SSG releases).
