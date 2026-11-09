#!/usr/bin/env bash
# examples/scripts/testing/validate_rendered_reports.sh
# Validates rendered compliance report files against expected content.
# Run after: ansible-playbook examples/scripts/testing/render_compliance_reports.yml
#
# Usage: bash examples/scripts/testing/validate_rendered_reports.sh
# Exit code: 0 = all checks passed, 1 = at least one check failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="${SCRIPT_DIR}/rendered_reports"
PASS=0
FAIL=0

# check_contains <file> <pattern> <description>
# Verifies that the file contains the grep pattern.
check_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "${pattern}" "${REPORTS_DIR}/${file}"; then
    echo "  ✅ ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  ❌ ${desc} (pattern not found: '${pattern}')"
    FAIL=$((FAIL + 1))
  fi
}

# check_not_contains <file> <pattern> <description>
# Verifies that the file does NOT contain the grep pattern.
check_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if ! grep -q "${pattern}" "${REPORTS_DIR}/${file}"; then
    echo "  ✅ ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  ❌ ${desc} (pattern was found but should not be: '${pattern}')"
    FAIL=$((FAIL + 1))
  fi
}

# check_file_exists <file>
# Verifies the rendered report file exists before running checks.
check_file_exists() {
  local file="$1"
  if [[ ! -f "${REPORTS_DIR}/${file}" ]]; then
    echo "  ❌ File not found: ${REPORTS_DIR}/${file}"
    FAIL=$((FAIL + 1))
    return 1
  fi
  return 0
}

echo "========================================================================"
echo "  Compliance Report Template Validation"
echo "========================================================================"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 1: All Green
# ─────────────────────────────────────────────────────────────────────────────
echo "[Scenario 1] all_green"
if check_file_exists "all_green.txt"; then
  check_contains "all_green.txt" "ABSOLUTE SUCCESS" "Report shows ABSOLUTE SUCCESS"
  check_contains "all_green.txt" "EXECUTIVE SUMMARY" "Executive Summary section present"
  check_contains "all_green.txt" "AUDIT AND SECURITY DETAIL" "Audit section present"
  check_contains "all_green.txt" "2-HUB FLEET" "Hub topology shows 2-hub fleet"
  check_contains "all_green.txt" "7 cluster(s)" "Spoke fleet count is 7"
  check_contains "all_green.txt" "Last Backup Age" "Backup age line present"
  check_not_contains "all_green.txt" "ANOMALIES DETECTED" "No anomalies flag"
  check_not_contains "all_green.txt" "SPLIT-BRAIN DETECTED" "No split-brain alert"
  check_not_contains "all_green.txt" "STALE" "No stale backup warning"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 2: Split-Brain
# ─────────────────────────────────────────────────────────────────────────────
echo "[Scenario 2] split_brain"
if check_file_exists "split_brain.txt"; then
  check_contains "split_brain.txt" "ANOMALIES DETECTED" "Report shows ANOMALIES DETECTED"
  check_contains "split_brain.txt" "SPLIT-BRAIN DETECTED" "Split-brain warning fires"
  check_contains "split_brain.txt" "Active Hubs: 2" "Shows 2 active Hubs"
  check_contains "split_brain.txt" "acm-primary-hub-sa" "Lists the primary Hub"
  check_contains "split_brain.txt" "acm-dr-hub-sa" "Lists the DR Hub"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 3: Degraded Addons
# ─────────────────────────────────────────────────────────────────────────────
echo "[Scenario 3] degraded_addons"
if check_file_exists "degraded_addons.txt"; then
  check_contains "degraded_addons.txt" "ANOMALIES DETECTED" "Report shows ANOMALIES DETECTED"
  check_contains "degraded_addons.txt" "DEGRADED" "Addon degradation detected"
  check_contains "degraded_addons.txt" "iks-spoke-01" "IKS Spoke listed"
  check_contains "degraded_addons.txt" "managed-serviceaccount" "MSA addon named"
  check_contains "degraded_addons.txt" "aks-spoke-01" "AKS Spoke listed"
  check_contains "degraded_addons.txt" "3 Spoke(s)" "Per-Spoke breakdown count"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 4: Multi-Hub Topology
# ─────────────────────────────────────────────────────────────────────────────
echo "[Scenario 4] multi_hub"
if check_file_exists "multi_hub.txt"; then
  check_contains "multi_hub.txt" "3-HUB FLEET" "Hub topology shows 3-hub fleet"
  check_contains "multi_hub.txt" "acm-dr-hub-02-sa" "Third Hub context present"
  check_contains "multi_hub.txt" "UNREACHABLE" "Unreachable passive Hub detected"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 5: Unreachable Spokes
# ─────────────────────────────────────────────────────────────────────────────
echo "[Scenario 5] unreachable_spokes"
if check_file_exists "unreachable_spokes.txt"; then
  check_contains "unreachable_spokes.txt" "ANOMALIES DETECTED" "Report shows ANOMALIES DETECTED"
  check_contains "unreachable_spokes.txt" "Unreachable (SKIPPED)" "Unreachable Spokes in summary"
  check_contains "unreachable_spokes.txt" "eks-spoke-01" "EKS Spoke listed as unreachable"
  check_contains "unreachable_spokes.txt" "gke-spoke-01" "GKE Spoke listed as unreachable"
  check_contains "unreachable_spokes.txt" "SPOKE(S) UNREACHABLE" "Unreachable section fires"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 6: Version Skew
# ─────────────────────────────────────────────────────────────────────────────
echo "[Scenario 6] version_skew"
if check_file_exists "version_skew.txt"; then
  check_contains "version_skew.txt" "VERSION CHANGE DETECTED" "Version change detected"
  check_contains "version_skew.txt" "2.13.6" "Source ACM version shown"
  check_contains "version_skew.txt" "2.14.2" "Destination ACM version shown"
  check_contains "version_skew.txt" "4.17.22" "Source OCP version shown"
  check_contains "version_skew.txt" "4.18.34" "Destination OCP version shown"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 7: Dry-Run
# ─────────────────────────────────────────────────────────────────────────────
echo "[Scenario 7] dry_run"
if check_file_exists "dry_run.txt"; then
  check_contains "dry_run.txt" "DRY-RUN" "Dry-run mode indicator present"
  check_contains "dry_run.txt" "simulation" "Simulation label in execution mode"
  check_contains "dry_run.txt" "NOT EVALUATED" "Residual state not evaluated in dry-run"
  # In dry-run with no other anomalies, residual spokes don't trigger anomalies
  check_contains "dry_run.txt" "ABSOLUTE SUCCESS" "Dry-run with residual spokes still shows success"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 8: Everything Broken
# ─────────────────────────────────────────────────────────────────────────────
echo "[Scenario 8] everything_broken"
if check_file_exists "everything_broken.txt"; then
  check_contains "everything_broken.txt" "ANOMALIES DETECTED" "Report shows ANOMALIES DETECTED"
  check_contains "everything_broken.txt" "SPLIT-BRAIN DETECTED" "Split-brain fires"
  check_contains "everything_broken.txt" "DEGRADED" "Degraded addons fire"
  check_contains "everything_broken.txt" "Non-Compliant" "Noncompliant policies fire"
  check_contains "everything_broken.txt" "not Synced" "Unhealthy GitOps fires"
  check_contains "everything_broken.txt" "PlacementDecision(s) with no resolved" "Empty placements fire"
  check_contains "everything_broken.txt" "without backup label" "Unprotected dashboards fire"
  check_contains "everything_broken.txt" "SPOKE(S) UNREACHABLE" "Unreachable Spokes fire"
  check_contains "everything_broken.txt" "STALE" "Stale backup warning fires"
  check_contains "everything_broken.txt" "NOT SUPPORTED" "Fleet incompatibility fires"
  check_contains "everything_broken.txt" "VERSION CHANGE DETECTED" "Version change fires"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo "========================================================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "========================================================================"

if [[ "${FAIL}" -gt 0 ]]; then
  echo "❌ Some checks failed. Review the output above."
  exit 1
fi

echo "✅ All checks passed."
exit 0
