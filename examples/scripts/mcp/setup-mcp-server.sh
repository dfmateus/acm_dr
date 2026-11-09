#!/usr/bin/env bash
# setup-mcp-server.sh
#
# Enable the AAP MCP server on an operator-managed OCP install.
# Idempotent: patching an already-enabled MCP section is a no-op.
#
# Usage:
#   bash examples/scripts/mcp/setup-mcp-server.sh \
#     --context <OCP_CONTEXT>                   required
#     [--aap-cr-name <NAME>]                    default: aap
#     [--mode read-only|read-write]             default: read-only
#     [--apply]
#
# Without --apply the script prints what it would do and exits. This is the
# default to prevent accidental changes on first run.
#
# After --apply completes, generate a token for the agent user via the AAP UI
# or the API snippet printed at the end. Then fill in .local/aap/aiops_mcp.env.
#
# See examples/mcp/docs/01-setup.md for the full step-by-step guide.

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
APPLY=false
OCP_CONTEXT=""
AAP_CR_NAME="aap"
MODE="read-only"
AAP_NAMESPACE="ansible-automation-platform"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)         APPLY=true;           shift ;;
    --context)       OCP_CONTEXT="$2";     shift 2 ;;
    --aap-cr-name)   AAP_CR_NAME="$2";     shift 2 ;;
    --mode)          MODE="$2";            shift 2 ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *)
      echo "❌ Unknown argument: $1"
      echo "   Run with --help for usage."
      exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [[ -z "$OCP_CONTEXT" ]]; then
  echo "❌ --context is required. Example: --context hub-01"
  exit 1
fi

if [[ "$MODE" != "read-only" && "$MODE" != "read-write" ]]; then
  echo "❌ --mode must be 'read-only' or 'read-write', got: ${MODE}"
  exit 1
fi

ALLOW_WRITE="false"
if [[ "$MODE" == "read-write" ]]; then
  ALLOW_WRITE="true"
fi

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
echo "🔎 Preflight checks"
echo "   Context: $(oc whoami --show-context --context "${OCP_CONTEXT}" 2>/dev/null || echo "${OCP_CONTEXT} (context check failed - verify oc login)")"
echo "   AAP CR:  ${AAP_CR_NAME}"
echo "   Mode:    ${MODE}"
echo "   Apply:   ${APPLY}"
echo ""

if [[ "$APPLY" == "false" ]]; then
  echo "🔎 Dry-run mode. Pass --apply to execute changes."
  echo ""
fi

# Confirm the AnsibleAutomationPlatform CR exists before proceeding
if ! oc get aap "${AAP_CR_NAME}" \
    -n "${AAP_NAMESPACE}" \
    --context "${OCP_CONTEXT}" \
    -o name > /dev/null 2>&1; then
  echo "❌ AnsibleAutomationPlatform CR '${AAP_CR_NAME}' not found in namespace '${AAP_NAMESPACE}'"
  echo "   Check the CR name with: oc get aap -n ${AAP_NAMESPACE} --context ${OCP_CONTEXT}"
  exit 1
fi
echo "✅ AnsibleAutomationPlatform/${AAP_CR_NAME} found"
echo ""

# ---------------------------------------------------------------------------
# Step 1: patch the CR
# ---------------------------------------------------------------------------
MCP_PATCH=$(cat <<EOF
{
  "spec": {
    "mcp": {
      "disabled": false,
      "allow_write_operations": ${ALLOW_WRITE},
      "extra_settings": [
        {
          "setting": "IGNORE_CERTIFICATE_ERRORS",
          "value": true
        }
      ]
    }
  }
}
EOF
)

echo "🔎 Step 1: patch AnsibleAutomationPlatform/${AAP_CR_NAME} (adds spec.mcp block)"
if [[ "$APPLY" == "true" ]]; then
  oc patch aap "${AAP_CR_NAME}" \
    -n "${AAP_NAMESPACE}" \
    --context "${OCP_CONTEXT}" \
    --type merge -p "${MCP_PATCH}"
  echo "✅ CR patched. Operator will create the AnsibleMCPServer CR within ~2 minutes."
else
  echo "   Would patch: ${MCP_PATCH}"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 2: wait for AnsibleMCPServer Ready
# ---------------------------------------------------------------------------
MCP_CR_NAME="${AAP_CR_NAME}-mcp"
echo "🔎 Step 2: wait for AnsibleMCPServer/${MCP_CR_NAME} to become Ready"

if [[ "$APPLY" == "true" ]]; then
  PHASE="False"
  for i in $(seq 1 30); do
    # AAP 2.7 operator uses Successful/Running/Failure conditions, not Ready.
    # Wait for Running=False (reconciliation done) and Failure=False (no errors).
    RUNNING=$(oc get ansiblemcpserver "${MCP_CR_NAME}" \
      -n "${AAP_NAMESPACE}" \
      --context "${OCP_CONTEXT}" \
      -o jsonpath='{.status.conditions[?(@.type=="Running")].status}' 2>/dev/null || echo "")
    FAILURE=$(oc get ansiblemcpserver "${MCP_CR_NAME}" \
      -n "${AAP_NAMESPACE}" \
      --context "${OCP_CONTEXT}" \
      -o jsonpath='{.status.conditions[?(@.type=="Failure")].status}' 2>/dev/null || echo "")

    if [[ "${FAILURE}" == "True" ]]; then
      echo "❌ AnsibleMCPServer reconciliation failed. Check: oc describe ansiblemcpserver ${MCP_CR_NAME} -n ${AAP_NAMESPACE} --context ${OCP_CONTEXT}"
      break
    fi

    if [[ "${RUNNING}" == "False" ]]; then
      echo "✅ AnsibleMCPServer reconciliation complete"
      break
    fi

    echo "   Waiting... (${i}/30, ~$((i * 10))s elapsed)"
    sleep 10
  done

  if [[ "${RUNNING}" != "False" && "${FAILURE}" != "True" ]]; then
    echo "⚠️  Still reconciling after 5 minutes. The pod may be up anyway."
    echo "   Check: oc get pod -n ${AAP_NAMESPACE} --context ${OCP_CONTEXT} | grep mcp"
    echo "   The script will continue; the Route is usually available before reconciliation finishes."
  fi
else
  echo "   Skipping wait in dry-run mode."
fi
echo ""

# ---------------------------------------------------------------------------
# Step 3: get the MCP server Route
# ---------------------------------------------------------------------------
echo "🔎 Step 3: get MCP server Route"
MCP_ROUTE=""

if [[ "$APPLY" == "true" ]]; then
  # Try label-based lookup first
  MCP_ROUTE=$(oc get route \
    -n "${AAP_NAMESPACE}" \
    --context "${OCP_CONTEXT}" \
    -l "app.kubernetes.io/name=${MCP_CR_NAME}" \
    -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")

  # Fallback: grep the route list for the MCP server name
  if [[ -z "${MCP_ROUTE}" ]]; then
    MCP_ROUTE=$(oc get route \
      -n "${AAP_NAMESPACE}" \
      --context "${OCP_CONTEXT}" \
      2>/dev/null \
      | grep "${MCP_CR_NAME}" \
      | awk '{print $2}' \
      | head -1 || echo "")
  fi

  if [[ -z "${MCP_ROUTE}" ]]; then
    echo "⚠️  Route not found automatically."
    echo "   Get it manually: oc get route -n ${AAP_NAMESPACE} --context ${OCP_CONTEXT} | grep mcp"
    MCP_ROUTE="<obtain-manually>"
  else
    echo "✅ Route: https://${MCP_ROUTE}"
  fi
else
  MCP_ROUTE="<obtained-at-apply-time>"
  echo "   Route will be available after --apply."
fi
echo ""

# ---------------------------------------------------------------------------
# Step 4: token creation instructions
# ---------------------------------------------------------------------------
AGENT_USER="aiops-readonly"
TOKEN_SCOPE="read"
if [[ "$MODE" == "read-write" ]]; then
  AGENT_USER="aiops-operator"
  TOKEN_SCOPE="write"
fi

echo "🔎 Step 4: create a Personal Access Token for the agent user"
echo "   User:  ${AGENT_USER}"
echo "   Scope: ${TOKEN_SCOPE}"
echo ""
echo "   Option A - via AAP UI:"
echo "   1. Access Management > Users > ${AGENT_USER}"
echo "   2. Tokens tab > Create token"
echo "   3. Application: leave blank  |  Scope: ${TOKEN_SCOPE}"
echo "   4. Copy the token (shown once)"
echo ""
echo "   Option B - via API (uses AAP_TOKEN from aap_token.env):"
echo ""
echo "     source .local/aap/aap_token.env"
echo "     USER_ID=\$(curl -sk \\"
echo "       \"\${AAP_URL}/api/gateway/v1/users/?username=${AGENT_USER}\" \\"
echo "       -H \"Authorization: Bearer \${AAP_TOKEN}\" \\"
echo "       | jq -r '.results[0].id // empty')"
echo "     curl -sk -X POST \\"
echo "       \"\${AAP_URL}/api/gateway/v1/tokens/\" \\"
echo "       -H \"Authorization: Bearer \${AAP_TOKEN}\" \\"
echo "       -H \"Content-Type: application/json\" \\"
echo "       -d \"{\\\"description\\\": \\\"AIOps MCP ${MODE}\\\", \\\"user\\\": \${USER_ID}, \\\"scope\\\": \\\"${TOKEN_SCOPE}\\\"}\" \\"
echo "       | jq -r '.token // empty'"
echo ""

# ---------------------------------------------------------------------------
# Step 5: write the env file
# ---------------------------------------------------------------------------
echo "🔎 Step 5: write env file"
ENV_OUT=".local/aap/aiops_mcp.env"

if [[ "$APPLY" == "true" ]]; then
  mkdir -p "$(dirname "${ENV_OUT}")"
  cat > "${ENV_OUT}" <<ENVEOF
MCP_SERVER_ROUTE=https://${MCP_ROUTE}
MCP_MODE=${MODE}
AGENT_USER=${AGENT_USER}
# Paste the token from step 4 here
AIOPS_TOKEN=<paste-token-here>
ENVEOF
  echo "✅ ${ENV_OUT} written."
  echo "   Fill in AIOPS_TOKEN after step 4, then configure your client:"
  echo "   See examples/mcp/docs/02-clients.md"
else
  echo "   Would write: ${ENV_OUT}"
  echo "   Contents would be:"
  cat <<ENVEOF
     MCP_SERVER_ROUTE=https://${MCP_ROUTE}
     MCP_MODE=${MODE}
     AGENT_USER=${AGENT_USER}
     AIOPS_TOKEN=<paste-token-here>
ENVEOF
fi

echo ""
echo "Done. Next step: generate the token for '${AGENT_USER}' (see step 4 above)."
