#!/usr/bin/env bash
# Cluster login and kubeconfig context registration for the ACM DR fleet.
# Maintained by: Diego Felipe Mateus (https://github.com/dfmateus)
# File: examples/scripts/cluster-onboarding/01_register_cluster.sh
#
# =============================================================================
# PURPOSE:
#   Authenticates to a cluster, validates cluster-admin privileges, and
#   registers a named context in the local KUBECONFIG. Supports four cluster
#   types via --cloud:
#     ocp  -- OpenShift / ARO (oc login with username + password)
#     aks  -- Azure Kubernetes Service (az aks get-credentials)
#     eks  -- Amazon EKS (aws eks update-kubeconfig --alias)
#     gke  -- Google Kubernetes Engine (gcloud container clusters get-credentials)
#
#   This script does NOT perform RHACM onboarding. Run it first, then call
#   02_provision_automation_sa.sh to create the automation ServiceAccount.
#
#   Runs interactively by default. Pass all required flags to skip prompts,
#   which is useful for CI or scripted multi-cluster onboarding.
#   The password is never accepted as a flag argument; pass it via the env var
#   named by --password-env to keep it out of the process list.
#
# USAGE:
#   ./01_register_cluster.sh [--cloud TYPE] [FLAGS] [--help]
#
# EXIT CODES:
#   0  -- success
#   1  -- usage error or operator abort
#   2  -- missing prerequisite binary
#   3  -- authentication or API error
# =============================================================================

set -euo pipefail

# ─── Colour constants ────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'  # reset

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [--cloud TYPE] [FLAGS] [--help]

Authenticates to a cluster and registers a named kubeconfig context.
Runs interactively when called with no flags; pass all required flags
to skip every prompt (useful for CI or scripted multi-cluster onboarding).

Options:
  --cloud TYPE          Cluster type (default: ocp)
                          ocp  OpenShift / ARO (oc login, username + password)
                          aks  Azure Kubernetes Service (az aks get-credentials)
                          eks  Amazon EKS (aws eks update-kubeconfig --alias)
                          gke  Google Kubernetes Engine (gcloud get-credentials)
  --help                Show this message and exit

OCP/ARO flags:
  --api-url URL         Cluster API endpoint (e.g. https://api.mycluster.example.com:6443)
  --username USER       Login username
  --password-env VAR    Name of the environment variable that holds the password.
                        Never pass the password itself as a flag -- it ends up in
                        the process list and shell history.

AKS flags:
  --rg RESOURCE_GROUP   Azure resource group containing the AKS cluster
  --cluster-name NAME   AKS cluster name

EKS flags:
  --region REGION       AWS region (e.g. us-east-1)
  --cluster-name NAME   EKS cluster name

GKE flags:
  --project PROJECT     GCP project ID
  --region REGION       Region or zone (e.g. us-central1 or us-central1-a)
  --cluster-name NAME   GKE cluster name

All cloud types:
  --context-name NAME   Kubeconfig context name to register.
                        OCP default: auto-detected from infrastructureName.
                        AKS/EKS/GKE default: the cluster name.

Examples (interactive):
  $(basename "$0")                   # OCP / ARO
  $(basename "$0") --cloud aks       # AKS
  $(basename "$0") --cloud eks       # EKS
  $(basename "$0") --cloud gke       # GKE

Examples (non-interactive):
  export OCP_PASS=secret
  $(basename "$0") --cloud ocp \\
    --api-url https://api.mycluster.example.com:6443 \\
    --username kubeadmin --password-env OCP_PASS \\
    --context-name acmdr-lab-hub-01

  $(basename "$0") --cloud aks \\
    --rg my-rg --cluster-name my-aks \\
    --context-name acmdr-spoke-01

Next steps after this script:
  1. $(basename "$(dirname "$0")")/02_provision_automation_sa.sh <context-name>
  2. ansible-playbook playbooks/manage-spoke.yml --tags spoke_prep ...

Known limitations:
  - IKS (IBM Cloud): VPC private endpoints are not reachable externally.
    Register the context manually via 'ibmcloud ks cluster config', then run
    script 02 directly.
  - GKE Autopilot: cluster-admin ClusterRoleBinding is denied by the Autopilot
    admission webhook. This script will warn but the SA provisioning will fail.
EOF
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
CLOUD_TYPE="ocp"    # default -- OCP / ARO via oc login
ARG_API_URL=""      # --api-url (ocp)
ARG_USERNAME=""     # --username (ocp)
ARG_PASSWORD_ENV="" # --password-env VARNAME (ocp) - never the password itself
ARG_RG=""           # --rg (aks)
ARG_CLUSTER_NAME="" # --cluster-name (aks/eks/gke)
ARG_REGION=""       # --region (eks/gke)
ARG_PROJECT=""      # --project (gke)
ARG_CONTEXT_NAME="" # --context-name (all types)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)          CLOUD_TYPE="${2:-}";        shift 2 ;;
    --api-url)        ARG_API_URL="${2:-}";        shift 2 ;;
    --username)       ARG_USERNAME="${2:-}";       shift 2 ;;
    --password-env)   ARG_PASSWORD_ENV="${2:-}";   shift 2 ;;
    --rg)             ARG_RG="${2:-}";             shift 2 ;;
    --cluster-name)   ARG_CLUSTER_NAME="${2:-}";   shift 2 ;;
    --region)         ARG_REGION="${2:-}";         shift 2 ;;
    --project)        ARG_PROJECT="${2:-}";        shift 2 ;;
    --context-name)   ARG_CONTEXT_NAME="${2:-}";   shift 2 ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}❌ [ERROR]: Unknown argument: $1${NC}" >&2
      usage
      exit 1
      ;;
  esac
done

# Abort early if --password-env was given but the named variable is unset or empty.
# Better to fail here than to log in with a blank password or get a confusing error.
if [[ -n "${ARG_PASSWORD_ENV}" && -z "${!ARG_PASSWORD_ENV:-}" ]]; then
  echo -e "${RED}❌ [ERROR]: --password-env '${ARG_PASSWORD_ENV}' is set but that variable is empty.${NC}" >&2
  echo -e "${RED}   Export the password first: export ${ARG_PASSWORD_ENV}=<value>${NC}" >&2
  exit 1
fi

# ─── Validate cloud type ──────────────────────────────────────────────────────
case "${CLOUD_TYPE}" in
  ocp|aks|eks|gke)
    ;;
  iks)
    echo -e "${RED}❌ [ERROR]: IKS is not supported by this script.${NC}"
    echo -e "${YELLOW}   IKS VPC API endpoints are private (no external access without VPN).${NC}"
    echo -e "${YELLOW}   Register the context manually:${NC}"
    echo -e "${YELLOW}     ibmcloud ks cluster config --cluster <name>  # writes to ~/.kube/config${NC}"
    echo -e "${YELLOW}   Then proceed directly to 02_provision_automation_sa.sh.${NC}"
    exit 1
    ;;
  *)
    echo -e "${RED}❌ [ERROR]: Unknown cloud type '${CLOUD_TYPE}'.${NC}" >&2
    echo -e "${RED}   Valid values: ocp, aks, eks, gke${NC}" >&2
    exit 1
    ;;
esac

# ─── Prerequisite checks ──────────────────────────────────────────────────────
# oc is always required: used for permission audit, context ops, and Hub detection.
if ! command -v oc >/dev/null 2>&1; then
  echo -e "${RED}❌ [CRITICAL]: 'oc' binary not found in PATH.${NC}" >&2
  echo -e "${RED}   Install: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html${NC}" >&2
  exit 2
fi

case "${CLOUD_TYPE}" in
  aks)
    if ! command -v az >/dev/null 2>&1; then
      echo -e "${RED}❌ [CRITICAL]: 'az' (Azure CLI) not found in PATH.${NC}" >&2
      echo -e "${RED}   Install: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli${NC}" >&2
      exit 2
    fi
    # Verify the user is logged in; fail early rather than on get-credentials.
    if ! az account show >/dev/null 2>&1; then
      echo -e "${RED}❌ [ERROR]: No active Azure session. Run 'az login' first.${NC}" >&2
      exit 2
    fi
    ;;
  eks)
    if ! command -v aws >/dev/null 2>&1; then
      echo -e "${RED}❌ [CRITICAL]: 'aws' (AWS CLI) not found in PATH.${NC}" >&2
      echo -e "${RED}   Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html${NC}" >&2
      exit 2
    fi
    # Verify the caller identity; fail early rather than on update-kubeconfig.
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
      echo -e "${RED}❌ [ERROR]: No active AWS session. Configure credentials or run 'aws sso login'.${NC}" >&2
      exit 2
    fi
    ;;
  gke)
    if ! command -v gcloud >/dev/null 2>&1; then
      echo -e "${RED}❌ [CRITICAL]: 'gcloud' (Google Cloud SDK) not found in PATH.${NC}" >&2
      echo -e "${RED}   Install: https://cloud.google.com/sdk/docs/install${NC}" >&2
      exit 2
    fi
    if ! gcloud auth print-access-token >/dev/null 2>&1; then
      echo -e "${RED}❌ [ERROR]: No active gcloud session. Run 'gcloud auth login' first.${NC}" >&2
      exit 2
    fi
    ;;
esac

# ─── Banner ───────────────────────────────────────────────────────────────────
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   ACM DR - Interactive Cluster Onboarding                  ${NC}"
echo -e "${BLUE}      Cloud type: ${CLOUD_TYPE^^}                                       ${NC}"
echo -e "${BLUE}============================================================${NC}"
echo -e "👋 This script will:"
echo -e "   1) Authenticate to the cluster (${CLOUD_TYPE})"
echo -e "   2) Check cluster-admin privileges"
echo -e "   3) Register a named kubeconfig context"
echo -e ""
echo -e "   ⚠️  RHACM onboarding is the next step: playbooks/manage-spoke.yml (spoke_prep)."
echo -e "${BLUE}============================================================${NC}"
echo ""

# CLUSTER_NAME_HINT is populated by the cloud-specific section and used as
# the default context name for non-OCP clusters (no Infrastructure CR available).
CLUSTER_NAME_HINT=""
AUTH_IDENTITY=""  # displayed in the final summary

# ─── Cloud-specific authentication ───────────────────────────────────────────

case "${CLOUD_TYPE}" in

  # ---------------------------------------------------------------------------
  # OCP / ARO - oc login with username + password
  # ---------------------------------------------------------------------------
  ocp)
    # API URL: use --api-url flag or prompt. Fail if neither is available.
    if [[ -n "${ARG_API_URL}" ]]; then
      API_URL="${ARG_API_URL}"
    elif [[ -t 0 ]]; then
      read -rp "🌐 Cluster API URL (e.g.: https://api.mycluster.example.com:6443): " API_URL
    else
      echo -e "${RED}❌ [ERROR]: --api-url is required in non-interactive mode.${NC}" >&2
      exit 1
    fi
    if [[ -z "${API_URL}" ]]; then
      echo -e "${RED}❌ [ERROR]: API URL cannot be empty.${NC}"
      exit 1
    fi

    # Username: use --username flag or prompt.
    if [[ -n "${ARG_USERNAME}" ]]; then
      CLUSTER_USER="${ARG_USERNAME}"
    elif [[ -t 0 ]]; then
      read -rp "👤 Username: " CLUSTER_USER
    else
      echo -e "${RED}❌ [ERROR]: --username is required in non-interactive mode.${NC}" >&2
      exit 1
    fi
    if [[ -z "${CLUSTER_USER}" ]]; then
      echo -e "${RED}❌ [ERROR]: username cannot be empty.${NC}"
      exit 1
    fi
    AUTH_IDENTITY="${CLUSTER_USER}"

    # Password: read from the named env var (--password-env) or prompt interactively.
    # Never accept the password as a direct flag argument -- it ends up in ps/history.
    if [[ -n "${ARG_PASSWORD_ENV}" ]]; then
      CLUSTER_PASSWORD="${!ARG_PASSWORD_ENV}"
    elif [[ -t 0 ]]; then
      read -rsp "🔑 Password: " CLUSTER_PASSWORD
      echo ""
    else
      echo -e "${RED}❌ [ERROR]: --password-env is required in non-interactive mode.${NC}" >&2
      exit 1
    fi
    if [[ -z "${CLUSTER_PASSWORD}" ]]; then
      echo -e "${RED}❌ [ERROR]: password cannot be empty.${NC}"
      exit 1
    fi

    echo -e "\n🔐 Authenticating to ${API_URL}..."
    LOGIN_OUTPUT=""
    if ! LOGIN_OUTPUT=$(oc login "${API_URL}" -u "${CLUSTER_USER}" -p "${CLUSTER_PASSWORD}" --insecure-skip-tls-verify=true 2>&1); then
      unset CLUSTER_PASSWORD
      echo -e "${RED}❌ [AUTHENTICATION ERROR]: unable to log in to '${API_URL}'.${NC}"
      echo -e "${RED}   Detail: ${LOGIN_OUTPUT}${NC}"
      exit 3
    fi
    unset CLUSTER_PASSWORD
    echo -e "${GREEN}✅ Login completed successfully.${NC}"
    ;;

  # ---------------------------------------------------------------------------
  # AKS - az aks get-credentials
  # Context name after this call: <cluster-name> (AKS default)
  # ---------------------------------------------------------------------------
  aks)
    if [[ -n "${ARG_RG}" ]]; then
      AKS_RESOURCE_GROUP="${ARG_RG}"
    elif [[ -t 0 ]]; then
      read -rp "☁️  Azure Resource Group: " AKS_RESOURCE_GROUP
    else
      echo -e "${RED}❌ [ERROR]: --rg is required in non-interactive mode.${NC}" >&2
      exit 1
    fi
    if [[ -z "${AKS_RESOURCE_GROUP}" ]]; then
      echo -e "${RED}❌ [ERROR]: resource group cannot be empty.${NC}"
      exit 1
    fi

    if [[ -n "${ARG_CLUSTER_NAME}" ]]; then
      AKS_CLUSTER_NAME="${ARG_CLUSTER_NAME}"
    elif [[ -t 0 ]]; then
      read -rp "🔠 AKS Cluster Name: " AKS_CLUSTER_NAME
    else
      echo -e "${RED}❌ [ERROR]: --cluster-name is required in non-interactive mode.${NC}" >&2
      exit 1
    fi
    if [[ -z "${AKS_CLUSTER_NAME}" ]]; then
      echo -e "${RED}❌ [ERROR]: cluster name cannot be empty.${NC}"
      exit 1
    fi
    CLUSTER_NAME_HINT="${AKS_CLUSTER_NAME}"
    AUTH_IDENTITY="$(az account show --query 'user.name' -o tsv 2>/dev/null || echo 'unknown')"

    echo -e "\n🔐 Fetching AKS credentials via 'az aks get-credentials'..."
    if ! az aks get-credentials \
         --resource-group "${AKS_RESOURCE_GROUP}" \
         --name "${AKS_CLUSTER_NAME}" \
         --file "${KUBECONFIG:-${HOME}/.kube/config}" \
         --overwrite-existing 2>&1; then
      echo -e "${RED}❌ [ERROR]: 'az aks get-credentials' failed.${NC}"
      echo -e "${RED}   Confirm your Azure session ('az account show') and cluster access.${NC}"
      exit 3
    fi
    # Switch to the cluster context explicitly; AKS sets the context name to the cluster name.
    oc config use-context "${AKS_CLUSTER_NAME}" >/dev/null 2>&1 || true
    echo -e "${GREEN}✅ AKS credentials fetched successfully.${NC}"
    ;;

  # ---------------------------------------------------------------------------
  # EKS - aws eks update-kubeconfig with --alias to avoid the ARN context name.
  # Without --alias, the context is arn:aws:eks:<region>:<account>:cluster/<name>.
  # ---------------------------------------------------------------------------
  eks)
    if [[ -n "${ARG_REGION}" ]]; then
      EKS_REGION="${ARG_REGION}"
    elif [[ -t 0 ]]; then
      read -rp "🌍 AWS Region (e.g.: us-east-1): " EKS_REGION
    else
      echo -e "${RED}❌ [ERROR]: --region is required in non-interactive mode.${NC}" >&2
      exit 1
    fi
    if [[ -z "${EKS_REGION}" ]]; then
      echo -e "${RED}❌ [ERROR]: region cannot be empty.${NC}"
      exit 1
    fi

    if [[ -n "${ARG_CLUSTER_NAME}" ]]; then
      EKS_CLUSTER_NAME="${ARG_CLUSTER_NAME}"
    elif [[ -t 0 ]]; then
      read -rp "🔠 EKS Cluster Name: " EKS_CLUSTER_NAME
    else
      echo -e "${RED}❌ [ERROR]: --cluster-name is required in non-interactive mode.${NC}" >&2
      exit 1
    fi
    if [[ -z "${EKS_CLUSTER_NAME}" ]]; then
      echo -e "${RED}❌ [ERROR]: cluster name cannot be empty.${NC}"
      exit 1
    fi
    CLUSTER_NAME_HINT="${EKS_CLUSTER_NAME}"
    AUTH_IDENTITY="$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo 'unknown')"

    echo -e "\n🔐 Fetching EKS credentials via 'aws eks update-kubeconfig'..."
    # --alias sets a human-readable context name instead of the full ARN.
    if ! aws eks update-kubeconfig \
         --region "${EKS_REGION}" \
         --name "${EKS_CLUSTER_NAME}" \
         --alias "${EKS_CLUSTER_NAME}" \
         --kubeconfig "${KUBECONFIG:-${HOME}/.kube/config}" 2>&1; then
      echo -e "${RED}❌ [ERROR]: 'aws eks update-kubeconfig' failed.${NC}"
      echo -e "${RED}   Confirm your AWS credentials and cluster access.${NC}"
      exit 3
    fi
    oc config use-context "${EKS_CLUSTER_NAME}" >/dev/null 2>&1 || true
    echo -e "${GREEN}✅ EKS credentials fetched successfully.${NC}"
    ;;

  # ---------------------------------------------------------------------------
  # GKE - gcloud container clusters get-credentials
  # Context name after this call: gke_<project>_<region>_<cluster-name>
  # The renaming step below will offer a shorter alias.
  # ---------------------------------------------------------------------------
  gke)
    if [[ -n "${ARG_PROJECT}" ]]; then
      GKE_PROJECT="${ARG_PROJECT}"
    elif [[ -t 0 ]]; then
      read -rp "📦 GCP Project ID: " GKE_PROJECT
    else
      echo -e "${RED}❌ [ERROR]: --project is required in non-interactive mode.${NC}" >&2
      exit 1
    fi
    if [[ -z "${GKE_PROJECT}" ]]; then
      echo -e "${RED}❌ [ERROR]: project ID cannot be empty.${NC}"
      exit 1
    fi

    if [[ -n "${ARG_REGION}" ]]; then
      GKE_REGION="${ARG_REGION}"
    elif [[ -t 0 ]]; then
      read -rp "🌍 Region or Zone (e.g.: us-central1 or us-central1-a): " GKE_REGION
    else
      echo -e "${RED}❌ [ERROR]: --region is required in non-interactive mode.${NC}" >&2
      exit 1
    fi
    if [[ -z "${GKE_REGION}" ]]; then
      echo -e "${RED}❌ [ERROR]: region/zone cannot be empty.${NC}"
      exit 1
    fi

    if [[ -n "${ARG_CLUSTER_NAME}" ]]; then
      GKE_CLUSTER_NAME="${ARG_CLUSTER_NAME}"
    elif [[ -t 0 ]]; then
      read -rp "🔠 GKE Cluster Name: " GKE_CLUSTER_NAME
    else
      echo -e "${RED}❌ [ERROR]: --cluster-name is required in non-interactive mode.${NC}" >&2
      exit 1
    fi
    if [[ -z "${GKE_CLUSTER_NAME}" ]]; then
      echo -e "${RED}❌ [ERROR]: cluster name cannot be empty.${NC}"
      exit 1
    fi
    CLUSTER_NAME_HINT="${GKE_CLUSTER_NAME}"
    AUTH_IDENTITY="$(gcloud config get-value account 2>/dev/null || echo 'unknown')"

    echo -e "\n🔐 Fetching GKE credentials via 'gcloud container clusters get-credentials'..."
    if ! KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}" \
         gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
         --region "${GKE_REGION}" \
         --project "${GKE_PROJECT}" 2>&1; then
      echo -e "${RED}❌ [ERROR]: 'gcloud container clusters get-credentials' failed.${NC}"
      echo -e "${RED}   Confirm your gcloud session and cluster access.${NC}"
      exit 3
    fi
    echo -e "${GREEN}✅ GKE credentials fetched successfully.${NC}"
    ;;

esac

ORIGINAL_CONTEXT="$(oc config current-context)"
echo -e "📍 Context after authentication: ${CYAN}${ORIGINAL_CONTEXT}${NC}"

# ─── Permission audit (cluster-admin) ────────────────────────────────────────
# Non-blocking: prints a warning but does not abort. The decision to continue is
# always the operator's. 'oc auth can-i' works for OCP and plain Kubernetes alike.
echo -e "\n🕵️  Validating cluster-admin privileges..."
CAN_ADMIN="no"
if oc auth can-i '*' '*' --all-namespaces --context="${ORIGINAL_CONTEXT}" >/dev/null 2>&1; then
  CAN_ADMIN="yes"
  echo -e "${GREEN}✅ Cluster-admin privileges confirmed.${NC}"
else
  echo -e "${YELLOW}⚠️  Cluster-admin privileges NOT confirmed.${NC}"
  echo -e "${YELLOW}   Script 02 (SA provisioning) and the acm_dr_spoke_manager role require${NC}"
  echo -e "${YELLOW}   cluster-admin to create ServiceAccount and ClusterRoleBinding.${NC}"
  if [[ "${CLOUD_TYPE}" == "gke" ]]; then
    echo -e "${YELLOW}   GKE Autopilot clusters deny cluster-admin by default - see --help.${NC}"
  fi
fi

# ─── Context naming ───────────────────────────────────────────────────────────
echo ""
if [[ -n "${ARG_CONTEXT_NAME}" ]]; then
  # --context-name was given on the command line; skip all prompts and detection.
  FINAL_CONTEXT_NAME="${ARG_CONTEXT_NAME}"
  echo -e "🏷️  Context name (from --context-name): ${CYAN}${FINAL_CONTEXT_NAME}${NC}"
elif [[ "${CLOUD_TYPE}" == "ocp" ]]; then
  # OCP: try to auto-detect from Infrastructure.status.infrastructureName
  if [[ -t 0 ]]; then
    read -rp "🏷️  Friendly context name (ENTER to auto-detect via infrastructureName): " CUSTOM_CONTEXT_NAME
  else
    CUSTOM_CONTEXT_NAME=""  # non-interactive: fall through to auto-detection
  fi
  if [[ -n "${CUSTOM_CONTEXT_NAME}" ]]; then
    FINAL_CONTEXT_NAME="${CUSTOM_CONTEXT_NAME}"
    echo -e "🏷️  Context name set manually: ${CYAN}${FINAL_CONTEXT_NAME}${NC}"
  else
    echo -e "🔍 Discovering 'infrastructureName' from the cluster..."
    INFRA_NAME=$(oc get infrastructure cluster \
                  --context="${ORIGINAL_CONTEXT}" \
                  -o jsonpath='{.status.infrastructureName}' 2>/dev/null || true)
    if [[ -z "${INFRA_NAME}" ]]; then
      echo -e "${RED}❌ [ERROR]: unable to retrieve 'infrastructureName'. Is this an OpenShift cluster?${NC}"
      echo -e "${RED}   Re-run the script and provide the context name with --context-name.${NC}"
      exit 1
    fi
    FINAL_CONTEXT_NAME="${INFRA_NAME}"
    echo -e "🏷️  Auto-detected 'infrastructureName': ${CYAN}${FINAL_CONTEXT_NAME}${NC}"
  fi
else
  # Non-OCP: no Infrastructure CR. Default to the cluster name passed earlier.
  if [[ -t 0 ]]; then
    read -rp "🏷️  Friendly context name (ENTER to use '${CLUSTER_NAME_HINT}'): " CUSTOM_CONTEXT_NAME
  else
    CUSTOM_CONTEXT_NAME=""
  fi
  FINAL_CONTEXT_NAME="${CUSTOM_CONTEXT_NAME:-${CLUSTER_NAME_HINT}}"
  echo -e "🏷️  Context name: ${CYAN}${FINAL_CONTEXT_NAME}${NC}"
fi

# ─── Context renaming (idempotent) ────────────────────────────────────────────
if [[ "${FINAL_CONTEXT_NAME}" == "${ORIGINAL_CONTEXT}" ]]; then
  echo -e "ℹ️  Context is already named '${FINAL_CONTEXT_NAME}'. No renaming needed."
elif oc config get-contexts -o name | grep -qx "${FINAL_CONTEXT_NAME}"; then
  echo -e "${RED}❌ [ERROR]: a context named '${FINAL_CONTEXT_NAME}' already exists in KUBECONFIG.${NC}"
  echo -e "${RED}   Re-run the script and choose a different name.${NC}"
  exit 1
else
  oc config rename-context "${ORIGINAL_CONTEXT}" "${FINAL_CONTEXT_NAME}" >/dev/null
  echo -e "${GREEN}✅ Context renamed: '${ORIGINAL_CONTEXT}' → '${FINAL_CONTEXT_NAME}'${NC}"
fi

FINAL_WHOAMI=$(oc whoami --context="${FINAL_CONTEXT_NAME}" 2>/dev/null || \
               oc config view --context="${FINAL_CONTEXT_NAME}" --minify \
                 -o jsonpath='{.users[0].name}' 2>/dev/null || true)

# ─── Best-effort detection of the active RHACM Hub ───────────────────────────
echo -e "\n🔎 Detecting which RHACM Hub is currently active..."
ACTIVE_HUB_CONTEXT=""
for HUB_CANDIDATE in acm-primary-hub-sa acm-dr-hub-sa; do
  if oc config get-contexts -o name | grep -qx "${HUB_CANDIDATE}"; then
    HUB_PAUSED=$(oc get backupschedule \
                   -n open-cluster-management-backup \
                   --context="${HUB_CANDIDATE}" \
                   -o jsonpath='{.items[0].spec.paused}' 2>/dev/null || true)
    if [[ "${HUB_PAUSED}" == "false" ]]; then
      ACTIVE_HUB_CONTEXT="${HUB_CANDIDATE}"
      break
    fi
  fi
done

# ─── Final summary ────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}                     📋 FINAL SUMMARY                       ${NC}"
echo -e "${BLUE}============================================================${NC}"
echo -e "☁️  Cloud type:          ${CLOUD_TYPE^^}"
echo -e "👤 Authenticated as:    ${AUTH_IDENTITY:-unknown}"
if [[ "${CAN_ADMIN}" == "yes" ]]; then
  echo -e "🛡️  Cluster-admin:       ${GREEN}✅ Confirmed${NC}"
else
  echo -e "🛡️  Cluster-admin:       ${YELLOW}⚠️  Not confirmed - review permissions before proceeding${NC}"
fi
echo -e "🏷️  Registered context:  ${CYAN}${FINAL_CONTEXT_NAME}${NC}"
if [[ -n "${FINAL_WHOAMI}" ]]; then
  echo -e "🕵️  Identity validation:  ${GREEN}✅ ${FINAL_WHOAMI}${NC}"
else
  echo -e "🕵️  Identity validation:  ${RED}❌ Failed${NC}"
fi
echo -e "${BLUE}------------------------------------------------------------${NC}"
echo -e "🚀 NEXT STEPS:"
echo ""
echo -e "1) Provision the Zero-Trust ServiceAccount on the new cluster:"
echo -e "   ${CYAN}./examples/scripts/cluster-onboarding/02_provision_automation_sa.sh ${FINAL_CONTEXT_NAME}${NC}"
echo ""
echo -e "2) Onboard as a Spoke via acm_dr_spoke_manager (tag spoke_prep)."
if [[ -n "${ACTIVE_HUB_CONTEXT}" ]]; then
  echo -e "   Active Hub detected: ${GREEN}${ACTIVE_HUB_CONTEXT}${NC} (BackupSchedule not paused)."
else
  echo -e "   ${YELLOW}⚠️  Unable to auto-detect the active Hub.${NC}"
  echo -e "   ${YELLOW}   Verify manually before proceeding:${NC}"
  echo -e "   ${YELLOW}   oc get backupschedule -n open-cluster-management-backup \\${NC}"
  echo -e "   ${YELLOW}     --context <hub-sa> -o jsonpath='{.items[0].spec.paused}'${NC}"
fi
echo ""
echo -e "   ${CYAN}ansible-playbook playbooks/manage-spoke.yml${NC} \\"
echo -e "   ${CYAN}  -e k8s_target_context=\"${ACTIVE_HUB_CONTEXT:-<hub-ativo-sa>}\"${NC} \\"
echo -e "   ${CYAN}  -e acm_dr_spoke_manager_spoke_k8s_context=\"${FINAL_CONTEXT_NAME}-sa\"${NC} \\"
echo -e "   ${CYAN}  -e acm_dr_spoke_manager_cluster_name=\"${FINAL_CONTEXT_NAME}\"${NC} \\"
if [[ "${CLOUD_TYPE}" != "ocp" ]]; then
  # Non-OCP Spokes need the cloud label set explicitly; it cannot be auto-detected from
  # the Infrastructure CR (which only exists on OpenShift clusters).
  case "${CLOUD_TYPE}" in
    aks) CLOUD_LABEL="Azure" ;;
    eks) CLOUD_LABEL="Amazon" ;;
    gke) CLOUD_LABEL="Google" ;;
    *)   CLOUD_LABEL="Other" ;;
  esac
  echo -e "   ${CYAN}  -e acm_dr_spoke_manager_cluster_cloud=\"${CLOUD_LABEL}\"${NC} \\"
fi
echo -e "   ${CYAN}  --tags \"spoke_prep\"${NC}"
echo ""
echo -e "   The role will automatically:"
echo -e "     • Provision bootstrap SA + permanent token on the Spoke"
echo -e "     • Inject the auto-import-secret into the Hub"
echo -e "     • Create ManagedCluster + KlusterletAddonConfig"
echo -e "     • Wait for reconciliation (3–7 minutes)"
echo -e "     • Assert JOINED=True and AVAILABLE=True"
echo -e "${BLUE}============================================================${NC}"
