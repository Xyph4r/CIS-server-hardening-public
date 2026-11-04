#!/usr/bin/env bash
# Scan -> remediate -> re-scan pipeline glue for CIS hardening.
#
# Usage:
#   ci/scan-remediate-rescan.sh <ansible-limit-pattern>
#   ci/scan-remediate-rescan.sh rocky9
#   ci/scan-remediate-rescan.sh all
#
# Runs an initial OpenSCAP scan, applies the matching Ansible CIS role(s),
# then re-scans so the "after" report is the evidence artifact. Does NOT
# auto-apply SCAP-generated remediation - see scap/README.md for why.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIMIT="${1:?Usage: $0 <ansible-limit-pattern>}"
INVENTORY="${REPO_ROOT}/ansible/inventory/hosts.ini"

if [[ ! -f "${INVENTORY}" ]]; then
  echo "Missing ${INVENTORY} - copy ansible/inventory/hosts.example.ini to hosts.ini and fill in real hosts first." >&2
  exit 1
fi

echo "==> [1/3] Baseline OpenSCAP scan (limit: ${LIMIT})"
ansible-playbook -i "${INVENTORY}" \
  "${REPO_ROOT}/scap/playbooks/scap_scan.yml" \
  --limit "${LIMIT}"

echo "==> [2/3] Applying CIS hardening (limit: ${LIMIT})"
ansible-playbook -i "${INVENTORY}" \
  "${REPO_ROOT}/ansible/site.yml" \
  --limit "${LIMIT}"

echo "==> [3/3] Post-remediation OpenSCAP scan (limit: ${LIMIT})"
ansible-playbook -i "${INVENTORY}" \
  "${REPO_ROOT}/scap/playbooks/scap_scan.yml" \
  --limit "${LIMIT}"

echo "==> Done. Compare reports under ${REPO_ROOT}/reports/<host>/ (before vs after timestamps)."
