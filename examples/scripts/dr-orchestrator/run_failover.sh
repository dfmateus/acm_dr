#!/usr/bin/env bash

# =============================================================================
# ACM DR ORCHESTRATOR WRAPPER
# Maintained by: Diego Felipe Mateus (https://github.com/dfmateus)
# =============================================================================
# Description: Interactive wrapper for safe validation and execution of
#              ACM DR failover and failback playbooks via Ansible.
#
# Supports two credential modes:
#   1. Per-cluster credentials (primary): ACM_DR_SOURCE_* + ACM_DR_DEST_* env
#      vars pre-loaded via examples/scripts/lib/load_cluster_env.sh, or picked interactively
#      from .env files in ~/.kube/clusters/.
#   2. Monolithic kubeconfig (legacy): picks contexts from the local KUBECONFIG
#      file, as before the per-cluster model was introduced.
# =============================================================================

set -euo pipefail

# Terminal output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PLAYBOOK_PATH="playbooks/orchestrate-dr-failover.yml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN} 🚀 ACM DR - FAILOVER ORCHESTRATOR INTERACTOR ${NC}"
echo -e "${CYAN}======================================================================${NC}"

# 1. Verify local prerequisites
if ! command -v oc &> /dev/null; then
    echo -e "${RED}❌ [CRITICAL ERROR]: The 'oc' utility is not installed in the local PATH.${NC}"
    exit 1
fi

if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}❌ [CRITICAL ERROR]: 'ansible-playbook' is not installed in the local PATH.${NC}"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo -e "${RED}❌ [CRITICAL ERROR]: 'curl' is not installed in the local PATH.${NC}"
    exit 1
fi

if [ ! -f "$PLAYBOOK_PATH" ]; then
    echo -e "${RED}❌ [CRITICAL ERROR]: File '$PLAYBOOK_PATH' not found. Please run from the project root.${NC}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Helper: validate API connectivity using bearer token (no kubeconfig needed)
# ---------------------------------------------------------------------------
# Hits the /api endpoint with the bearer token and checks the HTTP status code.
# Used by per-cluster mode to verify each Hub before starting the playbook.
validate_percluster_api() {
    local label="$1"    # display name for log messages
    local host="$2"     # Kubernetes API URL
    local token="$3"    # bearer token

    local http_code
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${token}" \
      "${host}/api" 2>/dev/null || echo "000")

    case "${http_code}" in
        200)
            echo -e "${GREEN}✅ ${label}: authenticated and reachable${NC}"
            return 0
            ;;
        401)
            echo -e "${RED}❌ ${label}: token rejected (HTTP 401 - expired or revoked)${NC}"
            return 1
            ;;
        000)
            echo -e "${RED}❌ ${label}: unreachable (connection failed to ${host})${NC}"
            return 1
            ;;
        *)
            echo -e "${YELLOW}⚠️  ${label}: unexpected HTTP ${http_code} from ${host}${NC}"
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Helper: extract user identity from a JWT bearer token (best-effort)
# ---------------------------------------------------------------------------
# Decodes the JWT payload to get the 'sub' claim (e.g., system:serviceaccount:...).
# Falls back to "SA token" if jq is not installed or the token is not a JWT.
get_token_identity() {
    local token="$1"
    # JWT payload = second dot-separated segment, base64url-encoded
    local payload
    payload=$(printf '%s' "${token}" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null || true)
    if [[ -n "${payload}" ]] && command -v jq &>/dev/null; then
        printf '%s' "${payload}" | jq -r '.sub // "unknown"' 2>/dev/null || echo "SA token"
    else
        echo "SA token"
    fi
}

# ---------------------------------------------------------------------------
# Helper: display the Source Hub safety warning banner
# ---------------------------------------------------------------------------
show_source_hub_warning() {
    local from_hub="$1"
    echo -e "${YELLOW}======================================================================${NC}"
    echo -e "${YELLOW} ⚠️  WARNING / CRITICAL SECURITY INFORMATION - SOURCE HUB             ${NC}"
    echo -e "${YELLOW}======================================================================${NC}"
    echo -e " 1. Ensure that cluster ${GREEN}'${from_hub}'${NC} is indeed the current ACTIVE leader."
    echo -e " 2. Confirm that the Spokes/Managed Clusters are connected to this Hub."
    echo -e " 3. If this Hub was previously in passive/fenced mode, determine whether"
    echo -e "    the 'allow_fenced_origin' flag should be enabled in the next step."
    echo -e "${YELLOW}======================================================================${NC}\n"
}

# 2. Operational Scenario Selection
echo -e "\n${YELLOW}🎯 [STEP 0/4] Select the Operational Scenario:${NC}\n"
echo -e "   ${CYAN}1)${NC} 🛡️  Disaster Recovery (DR) Failover / Failback"
echo -e "      Standard failover or failback of the RHACM control plane between Hub pairs."
echo -e "      Split-brain prevention, fleet reconnection, and compliance audit.\n"
echo -e "   ${CYAN}2)${NC} 🔧 Planned Maintenance Failover (Zero-Downtime Hub Upgrade)"
echo -e "      Failover the fleet to the DR Hub, upgrade the idle Hub (ACM/OCP/both),"
echo -e "      validate, then failback. The fleet never loses its managing Hub.\n"
echo -e "   ${CYAN}3)${NC} 🔎 DR Readiness Drill (Dry-Run Rehearsal)"
echo -e "      Simulate the entire failover pipeline against real clusters without"
echo -e "      applying changes. Validates backup integrity and operational readiness.\n"

while true; do
    read -rp "👉 Select scenario [1/2/3] (default: 1): " SCENARIO
    SCENARIO="${SCENARIO:-1}"
    if [[ "$SCENARIO" =~ ^[123]$ ]]; then
        break
    else
        echo -e "${RED}⚠️ Invalid selection. Please enter 1, 2, or 3.${NC}"
    fi
done

# Display scenario-specific guidance banner
case "$SCENARIO" in
    1)
        echo -e "\n${GREEN}✅ Scenario: Disaster Recovery (DR) Failover / Failback${NC}\n"
        ;;
    2)
        echo -e "\n${YELLOW}======================================================================${NC}"
        echo -e "${YELLOW} 🔧 PLANNED MAINTENANCE FAILOVER - ZERO-DOWNTIME UPGRADE WORKFLOW    ${NC}"
        echo -e "${YELLOW}======================================================================${NC}"
        echo -e " This script handles ONE direction of the switchover at a time."
        echo -e " The full Planned Maintenance workflow is a 5-step process:\n"
        echo -e "   ${CYAN}Step 1:${NC} FAILOVER fleet from Hub A (active) → Hub B (standby)"
        echo -e "   ${CYAN}Step 2:${NC} UPGRADE Hub A (now idle) - ACM, OCP, or both"
        echo -e "   ${CYAN}Step 3:${NC} VALIDATE Hub A post-upgrade (MCH Running, BSL Available)"
        echo -e "   ${CYAN}Step 4:${NC} FAILBACK fleet to Hub A (now upgraded)"
        echo -e "   ${CYAN}Step 5:${NC} UPGRADE Hub B at leisure to match Hub A's version\n"
        echo -e " You are about to execute ${GREEN}Step 1 or Step 4${NC} (one failover direction)."
        echo -e " After completion, this script will display the next steps."
        echo -e "${YELLOW}======================================================================${NC}\n"
        ;;
    3)
        echo -e "\n${CYAN}======================================================================${NC}"
        echo -e "${CYAN} 🔎 DR READINESS DRILL - SIMULATION MODE (NO REAL CHANGES)            ${NC}"
        echo -e "${CYAN}======================================================================${NC}"
        echo -e " The entire pipeline will run against real clusters using Kubernetes"
        echo -e " API-native check_mode/diff (dryRun=All). No resources will be modified."
        echo -e " Safety assertions (reversed-direction guard, etc.) run at full strength."
        echo -e "${CYAN}======================================================================${NC}\n"
        ;;
esac

# Planned Maintenance: ask for target ACM version (optional upgrade validation)
TARGET_ACM_VERSION=""
if [ "$SCENARIO" = "2" ]; then
    read -rp "❓ Target RHACM version for upgrade validation (e.g., 2.16) - leave empty to skip: " TARGET_ACM_VERSION
    if [ -n "$TARGET_ACM_VERSION" ]; then
        echo -e "${GREEN}   ➜ Target RHACM version: ${TARGET_ACM_VERSION} (preflight will validate compatibility)${NC}\n"
    fi
fi

# ===========================================================================
# HUB SELECTION - per-cluster credentials, .env file picker, or monolithic
# ===========================================================================
# All three paths set FROM_HUB, TO_HUB, FROM_USER, TO_USER before continuing
# to the execution parameters section below.
PERCLUSTER_MODE=false
CLUSTER_ENV_DIR="${HOME}/.kube/clusters"

# ---------------------------------------------------------------------------
# Path A: per-cluster env vars already loaded
# ---------------------------------------------------------------------------
# Detects ACM_DR_SOURCE_* + ACM_DR_DEST_* exported via load_cluster_env.sh
# before running this script, or injected by AAP credential types.
if [[ -n "${ACM_DR_SOURCE_HOST:-}" && -n "${ACM_DR_SOURCE_TOKEN:-}" && \
      -n "${ACM_DR_SOURCE_CONTEXT:-}" && \
      -n "${ACM_DR_DEST_HOST:-}" && -n "${ACM_DR_DEST_TOKEN:-}" && \
      -n "${ACM_DR_DEST_CONTEXT:-}" ]]; then
    PERCLUSTER_MODE=true

    echo -e "\n${GREEN}✅ [STEP 1/4] Per-cluster credentials detected in environment:${NC}\n"
    echo -e "   ${CYAN}SOURCE${NC} (ACTIVE / FROM): ${ACM_DR_SOURCE_CONTEXT} → ${ACM_DR_SOURCE_HOST}"
    echo -e "   ${CYAN}DEST${NC}   (PASSIVE / TO):  ${ACM_DR_DEST_CONTEXT}   → ${ACM_DR_DEST_HOST}\n"

    # Validate API connectivity on both Hubs
    echo -e "${BLUE}📡 Validating API connectivity on both Hubs...${NC}"

    if ! validate_percluster_api "Source Hub (${ACM_DR_SOURCE_CONTEXT})" \
         "${ACM_DR_SOURCE_HOST}" "${ACM_DR_SOURCE_TOKEN}"; then
        echo -e "${YELLOW}💡 Check the .env file or re-run provision_automation_sa.sh for this cluster.${NC}"
        exit 1
    fi
    FROM_USER=$(get_token_identity "${ACM_DR_SOURCE_TOKEN}")

    if ! validate_percluster_api "Dest Hub (${ACM_DR_DEST_CONTEXT})" \
         "${ACM_DR_DEST_HOST}" "${ACM_DR_DEST_TOKEN}"; then
        echo -e "${YELLOW}💡 Check the .env file or re-run provision_automation_sa.sh for this cluster.${NC}"
        exit 1
    fi
    TO_USER=$(get_token_identity "${ACM_DR_DEST_TOKEN}")

    FROM_HUB="${ACM_DR_SOURCE_CONTEXT}"
    TO_HUB="${ACM_DR_DEST_CONTEXT}"

    echo ""
    show_source_hub_warning "${FROM_HUB}"
fi

# ---------------------------------------------------------------------------
# Path B: interactive .env file picker
# ---------------------------------------------------------------------------
# If per-cluster vars were not pre-loaded, check for .env files generated by
# provision_automation_sa.sh and offer to pick SOURCE and DEST interactively.
if [[ "${PERCLUSTER_MODE}" == "false" ]]; then
    if [[ -d "${CLUSTER_ENV_DIR}" ]]; then
        mapfile -t _ALL_ENV_FILES < <(find "${CLUSTER_ENV_DIR}" -maxdepth 1 -name "*.env" -type f 2>/dev/null | sort)
    else
        _ALL_ENV_FILES=()
    fi

    # Only offer .env picker if at least 2 files exist (need SOURCE + DEST)
    if [[ ${#_ALL_ENV_FILES[@]} -ge 2 ]]; then
        echo -e "\n${YELLOW}🔍 [STEP 1/4] Credential source selection:${NC}\n"
        echo -e "   ${CYAN}1)${NC} 📄 Per-cluster .env files (${#_ALL_ENV_FILES[@]} found in ${CLUSTER_ENV_DIR}/)"
        echo -e "   ${CYAN}2)${NC} 📋 KUBECONFIG contexts (monolithic, legacy mode)\n"

        while true; do
            read -rp "👉 Credential source [1/2] (default: 1): " _CRED_SOURCE
            _CRED_SOURCE="${_CRED_SOURCE:-1}"
            if [[ "${_CRED_SOURCE}" =~ ^[12]$ ]]; then break; fi
            echo -e "${RED}⚠️ Invalid selection. Enter 1 or 2.${NC}"
        done

        if [[ "${_CRED_SOURCE}" == "1" ]]; then
            # Display numbered .env file list for SOURCE selection
            _ENV_COUNT="${#_ALL_ENV_FILES[@]}"
            echo -e "\n${CYAN}Available per-cluster credential files:${NC}"
            for i in "${!_ALL_ENV_FILES[@]}"; do
                printf "   ${CYAN}%2d)${NC} %s\n" "$((i + 1))" "$(basename "${_ALL_ENV_FILES[$i]}")"
            done
            echo ""

            # Pick SOURCE Hub .env file
            while true; do
                read -rp "👉 Select SOURCE Hub .env file [1-${_ENV_COUNT}]: " _SRC_NUM
                if [[ "${_SRC_NUM}" =~ ^[0-9]+$ ]] && [[ "${_SRC_NUM}" -ge 1 ]] && [[ "${_SRC_NUM}" -le "${_ENV_COUNT}" ]]; then
                    _SRC_ENV="${_ALL_ENV_FILES[$((_SRC_NUM - 1))]}"
                    echo -e "${GREEN}   ➜ Source: $(basename "${_SRC_ENV}")${NC}"
                    break
                fi
                echo -e "${RED}⚠️ Invalid. Enter a number between 1 and ${_ENV_COUNT}.${NC}"
            done

            # Re-display with SOURCE dimmed, pick DEST Hub .env file
            echo -e "\n${CYAN}Available per-cluster credential files:${NC}"
            for i in "${!_ALL_ENV_FILES[@]}"; do
                if [[ "${_ALL_ENV_FILES[$i]}" == "${_SRC_ENV}" ]]; then
                    printf "   ${CYAN}%2d)${NC} %s ${YELLOW}← SOURCE (selected)${NC}\n" \
                        "$((i + 1))" "$(basename "${_ALL_ENV_FILES[$i]}")"
                else
                    printf "   ${CYAN}%2d)${NC} %s\n" "$((i + 1))" "$(basename "${_ALL_ENV_FILES[$i]}")"
                fi
            done
            echo ""

            while true; do
                read -rp "👉 Select DEST Hub .env file [1-${_ENV_COUNT}]: " _DST_NUM
                if [[ "${_DST_NUM}" =~ ^[0-9]+$ ]] && [[ "${_DST_NUM}" -ge 1 ]] && [[ "${_DST_NUM}" -le "${_ENV_COUNT}" ]]; then
                    _DST_ENV="${_ALL_ENV_FILES[$((_DST_NUM - 1))]}"
                    if [[ "${_DST_ENV}" == "${_SRC_ENV}" ]]; then
                        echo -e "${RED}⚠️ Dest cannot be the same file as Source. Pick a different one.${NC}"
                        continue
                    fi
                    echo -e "${GREEN}   ➜ Dest: $(basename "${_DST_ENV}")${NC}"
                    break
                fi
                echo -e "${RED}⚠️ Invalid. Enter a number between 1 and ${_ENV_COUNT}.${NC}"
            done

            # Load the selected .env files via load_cluster_env.sh
            echo -e "\n${BLUE}📦 Loading per-cluster credentials...${NC}"
            if [[ ! -f "${SCRIPT_DIR}/../lib/load_cluster_env.sh" ]]; then
                echo -e "${RED}❌ examples/scripts/lib/load_cluster_env.sh not found - cannot load .env files.${NC}"
                exit 1
            fi
            # shellcheck source=../lib/load_cluster_env.sh
            source "${SCRIPT_DIR}/../lib/load_cluster_env.sh" source "${_SRC_ENV}"
            # shellcheck source=../lib/load_cluster_env.sh
            source "${SCRIPT_DIR}/../lib/load_cluster_env.sh" dest "${_DST_ENV}"

            # Validate API connectivity on both Hubs
            echo -e "\n${BLUE}📡 Validating API connectivity on both Hubs...${NC}"

            if ! validate_percluster_api "Source Hub (${ACM_DR_SOURCE_CONTEXT})" \
                 "${ACM_DR_SOURCE_HOST}" "${ACM_DR_SOURCE_TOKEN}"; then
                echo -e "${YELLOW}💡 Check the .env file or re-run provision_automation_sa.sh.${NC}"
                exit 1
            fi
            FROM_USER=$(get_token_identity "${ACM_DR_SOURCE_TOKEN}")

            if ! validate_percluster_api "Dest Hub (${ACM_DR_DEST_CONTEXT})" \
                 "${ACM_DR_DEST_HOST}" "${ACM_DR_DEST_TOKEN}"; then
                echo -e "${YELLOW}💡 Check the .env file or re-run provision_automation_sa.sh.${NC}"
                exit 1
            fi
            TO_USER=$(get_token_identity "${ACM_DR_DEST_TOKEN}")

            FROM_HUB="${ACM_DR_SOURCE_CONTEXT}"
            TO_HUB="${ACM_DR_DEST_CONTEXT}"
            PERCLUSTER_MODE=true

            echo ""
            show_source_hub_warning "${FROM_HUB}"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Path C: monolithic kubeconfig mode (legacy, unchanged behavior)
# ---------------------------------------------------------------------------
# Falls through here only when no per-cluster vars were detected or loaded.
# Existing code is preserved without re-indentation inside the conditional.
if [[ "${PERCLUSTER_MODE}" == "false" ]]; then

echo -e "\n${YELLOW}🔍 [STEP 1/4] Mapping locally available Kubernetes contexts:${NC}\n"
oc config get-contexts
echo ""

# Build a numbered array of context names for selection-by-number
mapfile -t CTX_ARRAY < <(oc config get-contexts -o name)
CTX_COUNT="${#CTX_ARRAY[@]}"

if [ "$CTX_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ [CRITICAL ERROR]: No Kubernetes contexts found in your kubeconfig.${NC}"
    exit 1
fi

# Display numbered context list for easy selection
echo -e "${CYAN}Available contexts:${NC}"
for i in "${!CTX_ARRAY[@]}"; do
    # 1-based index for human-friendly selection
    printf "   ${CYAN}%2d)${NC} %s\n" "$((i + 1))" "${CTX_ARRAY[$i]}"
done
echo ""

# 3. Source Hub Selection (FROM) - select by number
while true; do
    read -rp "👉 Select the SOURCE / ACTIVE CONTEXT (FROM) [1-${CTX_COUNT}]: " FROM_NUM
    # Validate: must be a number within range
    if [[ "$FROM_NUM" =~ ^[0-9]+$ ]] && [ "$FROM_NUM" -ge 1 ] && [ "$FROM_NUM" -le "$CTX_COUNT" ]; then
        FROM_HUB="${CTX_ARRAY[$((FROM_NUM - 1))]}"
        echo -e "${GREEN}   ➜ Selected: ${FROM_HUB}${NC}"
        break
    else
        echo -e "${RED}⚠️ Invalid selection. Please enter a number between 1 and ${CTX_COUNT}.${NC}"
    fi
done

# Validate Session/Token on Source Hub
echo -e "${BLUE}📡 Validating authentication and session on Source Hub ('$FROM_HUB')...${NC}"
if ! FROM_USER=$(oc whoami --context="$FROM_HUB" 2>/dev/null); then
    echo -e "${RED}❌ [AUTHENTICATION FAILURE]: Unable to authenticate on context '$FROM_HUB'.${NC}"
    echo -e "${YELLOW}💡 Action Required: Run 'oc login' for cluster '$FROM_HUB' before proceeding.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Successfully authenticated as '$FROM_USER' on Source Hub ('$FROM_HUB').${NC}\n"

# Source Hub Warning Banner
show_source_hub_warning "$FROM_HUB"

# 4. Target Hub Selection (TO) - select by number (same numbered list)
echo -e "\n${CYAN}Available contexts:${NC}"
for i in "${!CTX_ARRAY[@]}"; do
    # Dim the already-selected Source Hub so the operator knows it's taken
    if [ "${CTX_ARRAY[$i]}" == "$FROM_HUB" ]; then
        printf "   ${CYAN}%2d)${NC} %s ${YELLOW}← SOURCE (already selected)${NC}\n" "$((i + 1))" "${CTX_ARRAY[$i]}"
    else
        printf "   ${CYAN}%2d)${NC} %s\n" "$((i + 1))" "${CTX_ARRAY[$i]}"
    fi
done
echo ""

while true; do
    read -rp "👉 Select the TARGET / DR CONTEXT (TO) [1-${CTX_COUNT}]: " TO_NUM
    # Validate: must be a number within range
    if [[ "$TO_NUM" =~ ^[0-9]+$ ]] && [ "$TO_NUM" -ge 1 ] && [ "$TO_NUM" -le "$CTX_COUNT" ]; then
        TO_HUB="${CTX_ARRAY[$((TO_NUM - 1))]}"
        # Prevent selecting the same context as Source
        if [ "$TO_HUB" == "$FROM_HUB" ]; then
            echo -e "${RED}⚠️ The Target Hub cannot be the same as the Source Hub. Please choose a different context.${NC}"
        else
            echo -e "${GREEN}   ➜ Selected: ${TO_HUB}${NC}"
            break
        fi
    else
        echo -e "${RED}⚠️ Invalid selection. Please enter a number between 1 and ${CTX_COUNT}.${NC}"
    fi
done

# Validate Session/Token on Target Hub
echo -e "${BLUE}📡 Validating authentication and session on Target Hub ('$TO_HUB')...${NC}"
if ! TO_USER=$(oc whoami --context="$TO_HUB" 2>/dev/null); then
    echo -e "${RED}❌ [AUTHENTICATION FAILURE]: Unable to authenticate on context '$TO_HUB'.${NC}"
    echo -e "${YELLOW}💡 Action Required: Run 'oc login' for cluster '$TO_HUB' before proceeding.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Successfully authenticated as '$TO_USER' on Target Hub ('$TO_HUB').${NC}\n"

fi  # end of monolithic kubeconfig mode (Path C)

# 5. Configure Execution Parameters
echo -e "${YELLOW}⚙️ [STEP 3/4] Ansible Execution Parameters Configuration:${NC}"

# Planned Maintenance: auto-enable allow_fenced_origin (the origin Hub may have been
# fenced in a previous step of the maintenance workflow - e.g., Step 4 failback after
# Step 1 already paused the origin's BackupSchedule)
ALLOW_FENCED="false"
if [ "$SCENARIO" = "2" ]; then
    ALLOW_FENCED="true"
    echo -e "${GREEN}   ➜ allow_fenced_origin=true (auto-enabled for Planned Maintenance)${NC}"
else
    read -rp "❓ Allow fenced/paused origin (allow_fenced_origin=true)? [y/N]: " FENCED_OPT
    if [[ "$FENCED_OPT" =~ ^[Yy]$ ]]; then
        ALLOW_FENCED="true"
    fi
fi

# DR Readiness Drill: force dry-run mode - no production option
if [ "$SCENARIO" = "3" ]; then
    EXEC_MODE="1"
    echo -e "${CYAN}   ➜ Execution mode: DRY-RUN (forced for DR Readiness Drill)${NC}"
else
    echo -e "\n${YELLOW}🔎 EXECUTION MODE:${NC}"
    echo -e "   DRY-RUN simulates the entire pipeline via Kubernetes API check_mode/diff"
    echo -e "   (nothing is actually applied). Recommended for rehearsal before a real failover.\n"
    echo -e "   ${CYAN}1)${NC} 🔎 DRY-RUN only         - simulate, no real changes (safest)"
    echo -e "   ${CYAN}2)${NC} 🔥 PRODUCTION only       - real changes, skip dry-run"
    echo -e "   ${CYAN}3)${NC} 🔎🔥 DRY-RUN + PRODUCTION - validate first, then apply (recommended)\n"

    while true; do
        read -rp "👉 Select execution mode [1/2/3] (default: 1): " EXEC_MODE
        EXEC_MODE="${EXEC_MODE:-1}"
        if [[ "$EXEC_MODE" =~ ^[123]$ ]]; then
            break
        else
            echo -e "${RED}⚠️ Invalid selection. Please enter 1, 2, or 3.${NC}"
        fi
    done
fi

# 6. Summary and Final Confirmation
DIRECTION_VALUE="${FROM_HUB}_to_${TO_HUB}"

# Resolve scenario label for the summary banner
case "$SCENARIO" in
    1) SCENARIO_LABEL="🛡️  Disaster Recovery (DR) Failover / Failback" ;;
    2) SCENARIO_LABEL="🔧 Planned Maintenance Failover (Zero-Downtime Upgrade)" ;;
    3) SCENARIO_LABEL="🔎 DR Readiness Drill (Dry-Run Rehearsal)" ;;
esac

echo -e "\n${CYAN}======================================================================${NC}"
echo -e "${CYAN} 📋 DR FAILOVER / FAILBACK OPERATION SUMMARY                           ${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo -e " 🎯 OPERATIONAL SCENARIO:        ${GREEN}${SCENARIO_LABEL}${NC}"
echo -e " 🎛️  SOURCE HUB (ACTIVE / FROM):  ${GREEN}$FROM_HUB${NC} (User: $FROM_USER)"
echo -e " 🎛️  TARGET HUB (DR / TO):      ${GREEN}$TO_HUB${NC} (User: $TO_USER)"
echo -e " 🔀 COMPUTED DIRECTION:          ${GREEN}$DIRECTION_VALUE${NC}"
echo -e " 🛡️  ALLOW FENCED ORIGIN:        ${GREEN}$ALLOW_FENCED${NC}"
if [ -n "$TARGET_ACM_VERSION" ]; then
    echo -e " 🔄 TARGET RHACM VERSION:        ${GREEN}$TARGET_ACM_VERSION${NC}"
fi
case "$EXEC_MODE" in
    1) echo -e " 🔎 EXECUTION MODE:              ${CYAN}DRY-RUN (simulation, no real changes)${NC}" ;;
    2) echo -e " 🔥 EXECUTION MODE:              ${RED}PRODUCTION (real changes will be applied)${NC}" ;;
    3) echo -e " 🔎🔥 EXECUTION MODE:             ${YELLOW}DRY-RUN + PRODUCTION (validate first, then apply)${NC}" ;;
esac
echo -e " 📄 TARGET PLAYBOOK:             ${GREEN}$PLAYBOOK_PATH${NC}"
if [[ "${PERCLUSTER_MODE}" == "true" ]]; then
    echo -e " 🔑 CREDENTIAL MODE:             ${CYAN}Per-cluster (ACM_DR_SOURCE_*/ACM_DR_DEST_*)${NC}"
else
    echo -e " 🔑 CREDENTIAL MODE:             ${YELLOW}Monolithic KUBECONFIG (legacy)${NC}"
fi
echo -e "${CYAN}======================================================================${NC}\n"

case "$EXEC_MODE" in
    1)
        read -rp "🔎 Confirm the start of the SIMULATION (dry-run, no real changes)? [Y/n]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
            echo -e "\n${RED}🛑 Operation CANCELLED by the user. No resources were modified.${NC}"
            exit 0
        fi
        ;;
    2)
        read -rp "🔥 Are you sure you want to START the DR orchestrator now (REAL execution)? [y/N]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "\n${RED}🛑 Operation CANCELLED by the user. No resources were modified.${NC}"
            exit 0
        fi
        ;;
    3)
        read -rp "🔎🔥 Start DRY-RUN validation followed by PRODUCTION execution? [y/N]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "\n${RED}🛑 Operation CANCELLED by the user. No resources were modified.${NC}"
            exit 0
        fi
        ;;
esac

# 7. Ansible Playbook Execution

run_playbook() {
    local dry_run_flag="$1"
    local run_label="$2"

    echo -e "\n${GREEN}🚀 Launching Ansible Engine - ${run_label}...${NC}\n"

    local CMD=(
      ansible-playbook "$PLAYBOOK_PATH"
      -e "failover_direction=$DIRECTION_VALUE"
      -e "active_hub=$FROM_HUB"
      -e "passive_hub=$TO_HUB"
      -e "acm_dr_failover_manager_dry_run=$dry_run_flag"
      -e "skip_gates=true"
      -e "allow_fenced_origin=$ALLOW_FENCED"
    )

    # Pass target RHACM version for Planned Maintenance upgrade validation
    if [ -n "$TARGET_ACM_VERSION" ]; then
        CMD+=(-e "acm_dr_failover_manager_target_acm_version=$TARGET_ACM_VERSION")
    fi

    echo -e "${BLUE}Command: ${CMD[*]}${NC}\n"
    "${CMD[@]}"
}

case "$EXEC_MODE" in
    1)
        run_playbook "true" "DRY-RUN (simulation)"
        ;;
    2)
        run_playbook "false" "PRODUCTION (real changes)"
        ;;
    3)
        run_playbook "true" "PHASE 1/2 - DRY-RUN (validation)"

        echo -e "\n${GREEN}======================================================================${NC}"
        echo -e "${GREEN} ✅ DRY-RUN COMPLETED SUCCESSFULLY                                     ${NC}"
        echo -e "${GREEN}======================================================================${NC}"
        echo -e " The simulation passed. You may now proceed with the real execution.\n"

        read -rp "🔥 Proceed with PRODUCTION execution now? [y/N]: " PROD_CONFIRM
        if [[ ! "$PROD_CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "\n${YELLOW}🛑 PRODUCTION execution skipped by the user. Only the dry-run was performed.${NC}"
            exit 0
        fi

        run_playbook "false" "PHASE 2/2 - PRODUCTION (real changes)"
        ;;
esac

# 8. Post-Completion Guidance (scenario-specific next steps)
case "$SCENARIO" in
    2)
        # Planned Maintenance: show the next steps in the upgrade workflow
        echo -e "\n${YELLOW}======================================================================${NC}"
        echo -e "${YELLOW} 🔧 PLANNED MAINTENANCE - NEXT STEPS                                 ${NC}"
        echo -e "${YELLOW}======================================================================${NC}"
        echo -e " The failover direction ${GREEN}${DIRECTION_VALUE}${NC} completed."
        echo -e ""
        echo -e " If this was ${CYAN}Step 1${NC} (failover to the standby Hub):"
        echo -e "   1. Upgrade the now-idle Hub ${GREEN}${FROM_HUB}${NC} (ACM/OCP/both)"
        echo -e "      ${BLUE}oc patch subscription.operators.coreos.com advanced-cluster-management \\${NC}"
        echo -e "      ${BLUE}  -n open-cluster-management --type merge \\${NC}"
        echo -e "      ${BLUE}  -p '{\"spec\":{\"channel\":\"release-X.YY\"}}' \\${NC}"
        echo -e "      ${BLUE}  --context=${FROM_HUB}${NC}"
        echo -e "   2. Validate: MCH Running, BSL Available, BackupSchedule functional"
        echo -e "      ${BLUE}oc get mch -A --context=${FROM_HUB}${NC}"
        echo -e "   3. Run this script again for ${CYAN}Step 4${NC} (failback: ${TO_HUB} → ${FROM_HUB})"
        echo -e "   4. After failback, upgrade ${GREEN}${TO_HUB}${NC} to match"
        echo -e ""
        echo -e " If this was ${CYAN}Step 4${NC} (failback to the upgraded Hub):"
        echo -e "   1. Upgrade the remaining Hub ${GREEN}${FROM_HUB}${NC} to the same version"
        echo -e "   2. Both Hubs are now on the same version - maintenance complete"
        echo -e "${YELLOW}======================================================================${NC}"
        ;;
    3)
        # DR Readiness Drill: confirm rehearsal completed
        echo -e "\n${CYAN}======================================================================${NC}"
        echo -e "${CYAN} 🔎 DR READINESS DRILL COMPLETED                                      ${NC}"
        echo -e "${CYAN}======================================================================${NC}"
        echo -e " The simulation ran against real clusters with no changes applied."
        echo -e " Review the compliance report above to verify DR readiness."
        echo -e " If the drill passed, your DR infrastructure is validated."
        echo -e "${CYAN}======================================================================${NC}"
        ;;
esac
