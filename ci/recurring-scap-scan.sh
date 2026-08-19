#!/usr/bin/env bash
# Scan-only wrapper for periodic drift detection - does NOT remediate.
# Compares against nothing automatically; the point is to keep a
# timestamped history of results.xml per host so you can diff runs and spot
# config drift (a package upgrade reset a setting, someone hand-edited a
# file outside Ansible, new SCAP content flags something that didn't used
# to fail).
#
# No dedicated always-on control node assumed - this is meant to be run
# manually, or wired into whatever scheduling YOU have available (your own
# crontab, a Task Scheduler entry, etc. - only fires while that machine is
# actually on). See the bottom of this script's output for a crontab example.
#
# Usage:
#   ci/recurring-scap-scan.sh              # scan every host in cis_servers
#   ci/recurring-scap-scan.sh rocky10      # scan just one group/host

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIMIT="${1:-cis_servers}"
INVENTORY="${REPO_ROOT}/ansible/inventory/hosts.ini"

if [[ ! -f "${INVENTORY}" ]]; then
  echo "Missing ${INVENTORY} - copy ansible/inventory/hosts.example.ini to hosts.ini and fill in real hosts first." >&2
  exit 1
fi

echo "==> $(date -u +%Y-%m-%dT%H:%M:%SZ) - scanning (limit: ${LIMIT})"
ansible-playbook -i "${INVENTORY}" \
  "${REPO_ROOT}/scap/playbooks/scap_scan.yml" \
  --limit "${LIMIT}"

echo "==> Done. Reports under ${REPO_ROOT}/reports/<host>/ - diff a run's results.xml against the previous one to spot drift."
echo
echo "To run this on a schedule from your own machine (only fires while it's"
echo "powered on/awake) - add a line like this via 'crontab -e':"
echo "  0 6 * * * ${REPO_ROOT}/ci/recurring-scap-scan.sh >> ${REPO_ROOT}/reports/recurring-scan.log 2>&1"
