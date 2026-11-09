#!/usr/bin/env bash
# =============================================================================
# Namespace Finalizer Purge Script
# Maintained by: Diego Felipe Mateus (https://github.com/dfmateus)
# =============================================================================
set -euo pipefail

if ! command -v oc &> /dev/null; then
    echo "❌ [ERROR] The 'oc' binary was not found in the PATH."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ [ERROR] The 'jq' binary was not found in the PATH."
    exit 1
fi

TARGET_NS="${1:-}"

if [ -z "${TARGET_NS}" ]; then
  echo "❌ ERROR: Please provide the namespace name. Example: $0 my-stuck-namespace"
  exit 1
fi

echo "🔍 Checking the state of Namespace: ${TARGET_NS}..."

if ! oc get namespace "${TARGET_NS}" &>/dev/null; then
  echo "⚠️ Namespace '${TARGET_NS}' was not found or has already been removed."
  exit 0
fi

TEMP_JSON=$(mktemp)

# 1. Extract the namespace definition and remove the finalizers list from spec
oc get namespace "${TARGET_NS}" -o json | \
  jq '.spec.finalizers = []' > "${TEMP_JSON}"

# 2. Execute the PUT call directly to the OpenShift API on the /finalize route
echo "🧹 Removing Namespace finalizers via API Server..."
oc replace --raw "/api/v1/namespaces/${TARGET_NS}/finalize" -f "${TEMP_JSON}" > /dev/null

# 3. Temporary file cleanup
rm -f "${TEMP_JSON}"

echo "✅ Success: Finalizer removed. The Namespace '${TARGET_NS}' has been deleted from the cluster."
