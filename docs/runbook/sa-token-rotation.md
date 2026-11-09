# Runbook: ServiceAccount Token Rotation

**Severity:** Critical. Expired tokens cause all Ansible automation and manual **`oc`**/**`kubectl`** commands to fail with HTTP 401 against the affected cluster.

---

## Situation

The **`ansible-dr-orchestrator`** ServiceAccount uses long-lived tokens (**`kubernetes.io/service-account-token`** type, no expiry set at creation time). In practice, these tokens do not expire on their own, but they can become invalid if:

- The Secret was deleted manually or by a namespace cleanup
- The cluster was rebuilt or upgraded and the Secret UID changed
- An operator rotated credentials without updating the kubeconfig and AAP credentials
- The token was revoked via **`oc delete secret`** during an incident

Symptoms:
- **`oc get pods --context <cluster>-sa`** returns **`Unauthorized`** or **`Forbidden`**
- AAP job fails at Stage 00 with a cluster authentication error
- **`k8s_info`** tasks return a 401 status in AAP job output

---

## Prerequisites

```bash
export K8S_AUTH_KUBECONFIG="${HOME}/.kube/config-acm-lab-dr"
export KUBECONFIG="${K8S_AUTH_KUBECONFIG}"
```

You need cluster-admin access to the affected cluster via an ACTIVE credential (interactive **`oc login`** or a different SA that still works).

---

## Step 1: Identify the affected cluster(s)

```bash
# List all -sa contexts and test each one
for ctx in $(oc config get-contexts -o name | grep '\-sa$'); do
  echo -n "Testing ${ctx}: "
  oc whoami --context "${ctx}" 2>&1 | head -1
done
```

Contexts that return **`Unauthorized`** or **`error`** need token rotation.

---

## Step 2: Log in interactively to the affected cluster

For OCP clusters (ARO, ROSA):

```bash
# Get the API URL from the kubeconfig
API_URL=$(oc config view --context <CLUSTER_CONTEXT> -o jsonpath='{.clusters[0].cluster.server}')
oc login "${API_URL}" -u kubeadmin   # or your cluster-admin user
```

For non-OCP clusters (AKS, EKS, GKE): use the provider-native CLI to refresh credentials.

---

## Step 3: Re-provision the ServiceAccount and token

Run the idempotent SA provisioning script. It creates the SA if absent, creates or refreshes the token Secret, and updates the **`-sa`** kubeconfig context:

```bash
./examples/scripts/cluster-onboarding/02_provision_automation_sa.sh <CLUSTER_CONTEXT>
```

The script writes a fresh token to **`~/.kube/clusters/<CLUSTER_CONTEXT>-sa.env`**.

Verify the new token works:

```bash
oc whoami --context <CLUSTER_CONTEXT>-sa
# Expected: system:serviceaccount:ansible-automation:ansible-dr-orchestrator
```

---

## Step 4: Update the AAP credential

The AAP credential instance for this cluster holds a copy of the bearer token. After rotating the token, the credential must be updated or AAP jobs will continue to fail.

### Option A: AAP UI

1. In AAP: Resources > Credentials > select the credential for this cluster
2. Edit the API Bearer Token field with the value from **`~/.kube/clusters/<CLUSTER_CONTEXT>-sa.env`** (the **`CLUSTER_TOKEN`** field)
3. Save. Do not paste or log the token value in a ticket or chat.

### Option B: AAP API (scripted)

```bash
# Read the new token (never print it - store to variable only)
NEW_TOKEN=$(grep CLUSTER_TOKEN ~/.kube/clusters/<CLUSTER_CONTEXT>-sa.env | cut -d= -f2 | tr -d '"')

# Retrieve the credential ID
CRED_ID=$(curl -sk -u "admin:${AAP_ADMIN_PASS}" \
  "https://aap.example.com/api/controller/v2/credentials/?name=<CRED_NAME>" \
  | jq -r '.results[0].id')

# PATCH the token field - the token value is never echoed
curl -sk -u "admin:${AAP_ADMIN_PASS}" \
  -X PATCH "https://aap.example.com/api/controller/v2/credentials/${CRED_ID}/" \
  -H "Content-Type: application/json" \
  -d "{\"inputs\": {\"cluster_token\": \"${NEW_TOKEN}\"}}" > /dev/null

unset NEW_TOKEN
```

---

## Step 5: Verify end-to-end

```bash
# Confirm the SA context works locally
oc whoami --context <CLUSTER_CONTEXT>-sa
oc get managedclusters --context <CLUSTER_CONTEXT>-sa 2>/dev/null | head -5
```

Then run a dry-run failover from AAP to confirm the new credential is picked up.

---

## Step 6: Update the monolithic kubeconfig (if applicable)

If your environment uses the monolithic kubeconfig (**`~/.kube/config-acm-lab-dr`**) alongside per-cluster **`.env`** files, also refresh the token in the merged file:

```bash
# Rebuild the Spoke fleet kubeconfig from all .env files:
./examples/scripts/cluster-onboarding/03_build_spoke_fleet.sh --auto
# Then merge Hub contexts manually into config-acm-lab-dr if needed.
```

---

## Rotation schedule

Long-lived tokens have no expiry by default, but rotating them annually (or after any personnel change with access to the **`.env`** files) is good practice. Add a calendar reminder.
