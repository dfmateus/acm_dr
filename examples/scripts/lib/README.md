# scripts/lib: shared shell helper libraries

Shared functions sourced by scripts in sibling directories. Not executable on their own.

---

## load_cluster_env.sh

Maps a per-cluster **`.env`** file to role-prefixed environment variables consumed by the ACM DR playbooks and the [acm_dr_kubeconfig_resolver](../../roles/acm_dr_kubeconfig_resolver) role.

### Usage

```bash
source examples/scripts/lib/load_cluster_env.sh <role> <env-file>
```

| Parameter | Description |
|-----------|-------------|
| **`<role>`** | Logical role of the cluster in the operation. One of: **`target`**, **`source`**, **`dest`**, **`spoke`**. Controls which **`ACM_DR_*`** prefix is applied to the exported variables. |
| **`<env-file>`** | Path to the per-cluster **`.env`** file. Typically **`~/.kube/clusters/<context-name>.env`**. |

### Role-to-prefix mapping

| Role argument | Exported prefix | Playbooks that consume it |
|---------------|-----------------|--------------------------|
| **`target`** | **`ACM_DR_TARGET_`** | Hub Setup, Hub Cleanup, ArgoCD, Spoke Manager (Hub side) |
| **`source`** | **`ACM_DR_SOURCE_`** | Failover Orchestrator (currently ACTIVE Hub) |
| **`dest`** | **`ACM_DR_DEST_`** | Failover Orchestrator (currently PASSIVE Hub) |
| **`spoke`** | **`ACM_DR_SPOKE_`** | Spoke Manager (Spoke side) |

### Variables exported per role

Each **`.env`** file must define these keys (the script re-exports them with the appropriate prefix):

| Key in **`.env`** file | Exported as **`ACM_DR_<ROLE>_*`** | Description |
|--------------------|-------------------------------|-------------|
| **`CLUSTER_HOST`** | **`_HOST`** | Kubernetes API URL (e.g., **`https://api.mycluster.example.com:6443`**) |
| **`CLUSTER_TOKEN`** | **`_TOKEN`** | ServiceAccount bearer token |
| **`CLUSTER_CA_DATA`** | **`_CA_DATA`** | Base64-encoded CA certificate bundle (optional; leave empty for clusters with publicly trusted certs) |
| **`CLUSTER_CONTEXT`** | **`_CONTEXT`** | Kubeconfig context name (e.g., **`your-hub-01-sa`**) |

### **`.env`** file format

Generated automatically by [examples/scripts/cluster-onboarding/02_provision_automation_sa.sh](../cluster-onboarding/02_provision_automation_sa.sh). Files live at **`~/.kube/clusters/<context-name>.env`**:

```bash
CLUSTER_HOST="https://api.your-hub-01.example.com:6443"
CLUSTER_TOKEN="eyJhbGciOiJSUzI1NiIsImtpZCI6..."
CLUSTER_CA_DATA=""
CLUSTER_CONTEXT="your-hub-01-sa"
```

### Example: failover dry-run from CLI

```bash
source examples/scripts/lib/load_cluster_env.sh source ~/.kube/clusters/your-hub-01-sa.env
source examples/scripts/lib/load_cluster_env.sh dest   ~/.kube/clusters/your-hub-02-sa.env

ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e acm_dr_failover_manager_dry_run=true
```
