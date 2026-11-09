# acm_dr_cluster_onboard

Creates the **`ansible-dr-orchestrator`** ServiceAccount, ClusterRoleBinding, and
non-expiring token Secret on any Kubernetes or OpenShift cluster. Run once per cluster
before configuring permanent credentials in Ansible Automation Platform.

## Purpose

The other ACM DR roles connect to clusters using a dedicated, non-expiring bearer token
from the **`ansible-dr-orchestrator`** ServiceAccount. This role creates that identity from
scratch, using only a temporary cluster-admin credential, breaking the bootstrap
dependency on pre-existing credentials.

## Connection modes

The role works with any of these credential sources (checked in order):

| Source | How to supply |
|---|---|
| AAP built-in "OpenShift or Kubernetes API Bearer Token" | Attach the credential to the **`ACM DR - LAB - Cluster Bootstrap`** Job Template |
| **`K8S_AUTH_HOST`** + **`K8S_AUTH_API_KEY`** env vars | Export them before running locally |
| **`KUBECONFIG`** + **`k8s_target_context`** | Export **`KUBECONFIG`** and pass **`-e k8s_target_context=<ctx>`** |
| **`ACM_DR_TARGET_*`** env vars | Use the **`ACM DR - Target Cluster`** custom credential type |

## Role variables

All variables are in [defaults/main.yml](defaults/main.yml). Key ones:

| Variable | Default | Description |
|---|---|---|
| **`acm_dr_cluster_onboard_namespace`** | **`ansible-automation`** | Namespace for the SA and token Secret |
| **`acm_dr_cluster_onboard_sa_name`** | **`ansible-dr-orchestrator`** | ServiceAccount name |
| **`acm_dr_cluster_onboard_crb_name`** | **`ansible-dr-orchestrator-admin`** | ClusterRoleBinding name |
| **`acm_dr_cluster_onboard_token_secret`** | **`ansible-dr-orchestrator-token`** | Token Secret name |
| **`acm_dr_cluster_onboard_cluster_role`** | **`cluster-admin`** | ClusterRole to bind |
| **`acm_dr_cluster_onboard_cluster_name`** | **`""`** | Display name for the output message |
| **`acm_dr_cluster_onboard_token_wait_retries`** | **`6`** | Poll retries for token population |
| **`acm_dr_cluster_onboard_token_wait_delay`** | **`5`** | Seconds between retries |

## Usage

### Via AAP (recommended)

1. Create a credential in AAP of type **"OpenShift or Kubernetes API Bearer Token"** (built-in)
   with your temporary cluster-admin token.
2. Run the **`ACM DR - LAB - Cluster Bootstrap`** Job Template, attaching the temporary credential.
3. Copy the **`oc get secret`** command from the job output and run it locally to retrieve the SA token.
4. Create a permanent credential of type **`ACM DR - Target Cluster`** with the SA token.
5. Revoke or deactivate the temporary credential.

### Locally (ansible-navigator)

```bash
export K8S_AUTH_HOST="https://api.<cluster>.<domain>:6443"
export K8S_AUTH_API_KEY="<cluster-admin-token>"

ansible-navigator run playbooks/bootstrap-cluster.yml \
  -e acm_dr_cluster_onboard_cluster_name="hub-primary"
```

Or with an existing kubeconfig context:

```bash
ansible-navigator run playbooks/bootstrap-cluster.yml \
  -e k8s_target_context="hub-primary-admin" \
  -e acm_dr_cluster_onboard_cluster_name="hub-primary"
```

## Security

- The bearer token value is **never printed** to AAP job logs or terminal output.
- Task 3.1.1 reads the Secret with **`no_log: true`**.
- Task 4.1.1 prints only the **`oc get secret`** command the operator must run locally.
- The temporary cluster-admin credential should be revoked after the permanent one is created.

## Idempotency

All Kubernetes resources use **`state: present`**. Re-running against a cluster that already
has the SA is safe. Kubernetes no-ops on matching objects.

## What is created

```
Namespace:            <acm_dr_cluster_onboard_namespace>          (default: ansible-automation)
ServiceAccount:       <acm_dr_cluster_onboard_sa_name>            (default: ansible-dr-orchestrator)
ClusterRoleBinding:   <acm_dr_cluster_onboard_crb_name>           (default: ansible-dr-orchestrator-admin)
Secret (token):       <acm_dr_cluster_onboard_token_secret>       (default: ansible-dr-orchestrator-token)
```

The Secret type is **`kubernetes.io/service-account-token`**. Kubernetes populates **`.data.token`**
automatically within a few seconds of the Secret being created.
