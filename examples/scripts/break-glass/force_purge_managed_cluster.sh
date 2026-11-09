#!/usr/bin/env bash
# =============================================================================
# Script: force_purge_managed_cluster.sh
# Description: Force-purge ManagedClusters and Namespaces stuck in
#              Terminating state on Red Hat ACM Hubs due to orphaned finalizers.
# Support: Interactive input or CLI arguments (accepts space or comma separated).
# Maintained by: Diego Felipe Mateus (https://github.com/dfmateus)
# =============================================================================

set -euo pipefail

# Output Colorization
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. Required Tools Check
for cmd in oc jq tr; do
  if ! command -v "$cmd" &> /dev/null; then
    echo -e "${RED}❌ [CRITICAL ERROR]: The tool '$cmd' is not installed or missing from the PATH.${NC}"
    exit 1
  fi
done

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN} 🧹 ACM DR - HUB & SPOKE PURGE UTILITY${NC}"
echo -e "${CYAN}======================================================================${NC}\n"

# 2. Parameter Capture (Interactive or CLI)
HUB_CONTEXT="${1:-}"

if [ -z "$HUB_CONTEXT" ]; then
  read -rp "👉 Enter the Target Hub context (e.g.: acm-dr-hub): " HUB_CONTEXT
fi

# Hub Context Validation
if [ -z "$HUB_CONTEXT" ]; then
  echo -e "${RED}❌ [ERROR]: The Hub context cannot be empty.${NC}"
  exit 1
fi

# Spokes Handling
shift 2>/dev/null || true
SPOKES_INPUT="$*"

if [ -z "$SPOKES_INPUT" ]; then
  echo -e ""
  read -rp "👉 Enter the names of the Spokes to purge (separated by space or comma): " SPOKES_INPUT
fi

if [ -z "$SPOKES_INPUT" ]; then
  echo -e "${RED}❌ [ERROR]: No Spoke was provided for purging.${NC}"
  exit 1
fi

# Input sanitization: replaces commas with spaces and converts to Bash array
SANITIZED_SPOKES=$(echo "$SPOKES_INPUT" | tr ',' ' ')
read -r -a SPOKES <<< "$SANITIZED_SPOKES"

# 3. Hub Connectivity Test
echo -e "\n${BLUE}🔍 Testing connectivity to Hub Context: '${HUB_CONTEXT}'...${NC}"
if ! oc cluster-info --context="${HUB_CONTEXT}" &> /dev/null; then
  echo -e "${RED}❌ [ERROR]: Failed to authenticate on context '${HUB_CONTEXT}'. Please verify that your 'oc login' is active.${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Successfully authenticated on Hub Context: '${HUB_CONTEXT}'${NC}\n"

# 4. Safety Confirmation before Execution
echo -e "${YELLOW}⚠️ PURGE OPERATION SUMMARY:${NC}"
echo -e "   ├─ Target Hub:    ${CYAN}${HUB_CONTEXT}${NC}"
echo -e "   └─ Target Spokes: ${CYAN}${SPOKES[*]}${NC}\n"

read -rp "Do you want to proceed with removal and finalizer bypass? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}⏹️ Operation cancelled by the user.${NC}"
  exit 0
fi

# 5. Spoke Fleet Processing
for SPOKE in "${SPOKES[@]}"; do
  echo -e "\n${YELLOW}======================================================================${NC}"
  echo -e "${BLUE}🚀 STARTING PURGE AND REMEDIATION OF SPOKE: ${SPOKE}${NC}"
  echo -e "${YELLOW}======================================================================${NC}"

  # Step A: Delete and Unlock the ManagedCluster resource
  echo -e "🧹 [1/5] Removing ManagedCluster '${SPOKE}'..."
  oc delete managedcluster "${SPOKE}" --context="${HUB_CONTEXT}" --ignore-not-found=true --timeout=10s 2>/dev/null || true
  oc patch managedcluster "${SPOKE}" --context="${HUB_CONTEXT}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true

  # Step B: Clean up ObservabilityAddons in the Namespace
  echo -e "🧹 [2/5] Removing ObservabilityAddon finalizers in namespace '${SPOKE}'..."
  oc patch observabilityaddon observability-addon -n "${SPOKE}" --context="${HUB_CONTEXT}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true

  # Step C: Clean up residual ManifestWorks
  echo -e "🧹 [3/5] Purging ManifestWorks finalizers in namespace '${SPOKE}'..."
  for MW in $(oc get manifestwork -n "${SPOKE}" --context="${HUB_CONTEXT}" -o name 2>/dev/null || true); do
    oc patch "$MW" -n "${SPOKE}" --context="${HUB_CONTEXT}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  done

  # Step D: Clean up KlusterletAddonConfig
  echo -e "🧹 [4/5] Removing KlusterletAddonConfig finalizers for '${SPOKE}'..."
  oc patch klusterletaddonconfig "${SPOKE}" -n "${SPOKE}" --context="${HUB_CONTEXT}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true

  # Step E: Force Cleanup of the Namespace /finalize sub-resource
  echo -e "🧹 [5/5] Executing API Server finalizer bypass on Namespace '${SPOKE}'..."
  if oc get ns "${SPOKE}" --context="${HUB_CONTEXT}" &>/dev/null; then
    oc get ns "${SPOKE}" --context="${HUB_CONTEXT}" -o json 2>/dev/null \
      | jq '.spec.finalizers = []' \
      | oc replace --raw "/api/v1/namespaces/${SPOKE}/finalize" --context="${HUB_CONTEXT}" -f - 2>/dev/null || true
  fi

  # Step F: Purge Validation (Polling)
  echo -e "⏳ Verifying complete purge of namespace '${SPOKE}'..."
  RETRIES=0
  MAX_RETRIES=10
  NS_EXISTS=true

  while [ $RETRIES -lt $MAX_RETRIES ]; do
    if ! oc get ns "${SPOKE}" --context="${HUB_CONTEXT}" &>/dev/null; then
      NS_EXISTS=false
      break
    fi
    sleep 2
    ((RETRIES++))
  done

  if [ "$NS_EXISTS" = false ]; then
    echo -e "${GREEN}✅ [SUCCESS]: Spoke and Namespace '${SPOKE}' fully removed from Hub '${HUB_CONTEXT}'!${NC}"
  else
    echo -e "${YELLOW}⚠️ [WARNING]: The namespace '${SPOKE}' is still completing asynchronous purge on the API Server.${NC}"
  fi
done

echo -e "\n${GREEN}🚀 OPERATION COMPLETED: Hub '${HUB_CONTEXT}' has been purged and is ready for re-import!${NC}"
