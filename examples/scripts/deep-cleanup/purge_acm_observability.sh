#!/usr/bin/env bash
# ==============================================================================
# Script: purge_acm_observability.sh
# Purpose: Complete purge of corrupted RHACM Observability resources
# ==============================================================================

set -euo pipefail

# Context and Namespace Variable Configuration
TARGET_CONTEXT="${1:-acm-primary-hub}"
OBSERVABILITY_NS="open-cluster-management-observability"

echo "======================================================================"
echo "🚀 [RHACM DR LAB] Starting Observability (Thanos) purge"
echo "🎯 Context: ${TARGET_CONTEXT}"
echo "📦 Namespace: ${OBSERVABILITY_NS}"
echo "======================================================================"

# 1. Prerequisite validation
if ! command -v oc &> /dev/null; then
    echo "❌ [ERROR] The 'oc' binary was not found in the PATH."
    exit 1
fi

# 2. Remove the Primary Custom Resource (MultiClusterObservability)
echo ""
echo "⏳ [1/4] Deleting the MultiClusterObservability CR (Triggering Garbage Collector)..."
oc delete multiclusterobservability observability \
    --context="${TARGET_CONTEXT}" \
    --wait=true \
    --timeout=120s || echo "⚠️ [WARNING] Resources already removed or timeout reached."

# 3. Delete the Secret with corrupted credentials
echo ""
echo "⏳ [2/4] Removing Secret 'thanos-object-storage'..."
oc delete secret thanos-object-storage \
    -n "${OBSERVABILITY_NS}" \
    --context="${TARGET_CONTEXT}" \
    --ignore-not-found

# 4. Clean up all orphaned PersistentVolumeClaims (PVCs)
echo ""
echo "⏳ [3/4] Removing all stuck PersistentVolumeClaims (PVCs)..."
oc delete pvc --all \
    -n "${OBSERVABILITY_NS}" \
    --context="${TARGET_CONTEXT}" \
    --ignore-not-found || true

# 5. Residual Pod state check
echo ""
echo "🔍 [4/4] Checking final pod state in namespace '${OBSERVABILITY_NS}'..."
oc get pods \
    -n "${OBSERVABILITY_NS}" \
    --context="${TARGET_CONTEXT}" || echo "ℹ️ Namespace '${OBSERVABILITY_NS}' not found or no residual pods."

echo ""
echo "======================================================================"
echo "✅ [SUCCESS] Purge completed! The cluster is ready for Ansible re-execution."
echo "======================================================================"
