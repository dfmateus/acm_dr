# acm_dr_msa_provisioner

Provisions a **`ManagedServiceAccount`** (MSA) CR and a **`ManifestWork`** **`ClusterRoleBinding`** on a RHACM Hub for a single Spoke cluster. The RHACM klusterlet handles all Spoke-side work: it creates the **`ServiceAccount`** on the Spoke and writes the auto-rotated token **`Secret`** back to the Hub.

This role is an opt-in companion to **[`acm_dr_spoke_manager`](../acm_dr_spoke_manager)** **`action=onboard`**. Enable it by setting **`acm_dr_spoke_manager_msa_enabled: true`**. It can also run standalone via **`playbooks/manage-spoke.yml`**.

## Why MSA instead of infinite credentials

| Aspect | SA + infinite credentials | ACM MSA |
|---|---|---|
| Credential lifetime | Infinite, never expires | Configurable TTL + auto-rotation |
| Per-cluster setup | Manual on each cluster | One MSA CR on Hub |
| Blast radius of leak | Full access, forever | Time-bounded, auto-expires |
| Revocation | Manual per cluster | Delete MSA on Hub, klusterlet cleans Spoke |
| Requires ACM | No | Yes (managed-serviceaccount addon) |

The permanent **`ansible-dr-orchestrator`** SA (created by **`acm_dr_spoke_manager`**) remains the primary credential for Stage 07 reconnection. MSA tokens are corrupted after OADP Restore ([KCS 7039710](https://access.redhat.com/solutions/7039710)) and cannot bootstrap reconnection. MSA is used for:

- **Stage 07b**: EE-to-Spoke API reachability verification after failover (**`acm_dr_failover_manager_enable_msa_verification: true`**)
- **`infra.support_assist`**: must-gather on any Spoke via **`acm_hub_token_resolver`** (**`acm_hub_token_resolver_msa_name: "ansible-dr-orchestrator-msa"`**)
- **Future automations**: compliance audit, workload validation, diagnostic collection. Any Ansible job with Hub credentials can reach all registered Spokes through this MSA.

## Prerequisites

| # | Requirement | Notes |
|---|---|---|
| 1 | RHACM Hub managing the target Spoke | Hub API reachable from the AAP EE |
| 2 | **`managed-serviceaccount`** addon enabled | Enable in **`MultiClusterEngine`** spec under **`overrides.components`** or via **`ManagedClusterAddOn`** CR per Spoke |
| 3 | Hub kubeconfig context available to the EE | Via the **`ACM DR - Target Cluster`** custom credential type |

The role checks for the **`ManagedServiceAccount`** CRD in preflight and fails with an actionable error if the addon is absent.

## Role variables

All variables are in **[`defaults/main.yml`](defaults/main.yml)**:

| Variable | Default | Description |
|---|---|---|
| **`acm_dr_msa_provisioner_hub_context`** | **`""`** | Hub kubeconfig context **(Required)** |
| **`acm_dr_msa_provisioner_spoke_name`** | **`""`** | **`ManagedCluster`** name = Hub namespace **(Required)** |
| **`acm_dr_msa_provisioner_msa_name`** | **`ansible-dr-orchestrator-msa`** | MSA CR name and token Secret name |
| **`acm_dr_msa_provisioner_ttl`** | **`720h`** | Token validity (30 days); must exceed the longest DR drill cycle |
| **`acm_dr_msa_provisioner_cluster_role`** | **`cluster-admin`** | ClusterRole bound by the ManifestWork CRB on the Spoke |
| **`acm_dr_msa_provisioner_sa_namespace`** | **`open-cluster-management-agent-addon`** | SA namespace on the Spoke (managed by the addon controller) |
| **`acm_dr_msa_provisioner_wait_retries`** | **`18`** | Poll retries for the token Secret to appear (180 seconds total) |
| **`acm_dr_msa_provisioner_wait_delay`** | **`10`** | Seconds between retries |
| **`acm_dr_msa_provisioner_debug_no_log`** | **`true`** | Set to false to show token values in task output (debug only) |

## What is created

All objects are Hub-side. The klusterlet handles Spoke-side creation automatically.

```
ManagedServiceAccount:  <spoke-name>/<acm_dr_msa_provisioner_msa_name>    (Hub)
ManifestWork:           <spoke-name>/<acm_dr_msa_provisioner_msa_name>-rbac  (Hub)
  └── ClusterRoleBinding: <msa-name>-admin → cluster-admin                (Spoke, via klusterlet)
  └── ServiceAccount:   <msa-name> in open-cluster-management-agent-addon (Spoke, via klusterlet)
Secret (token):         <spoke-name>/<acm_dr_msa_provisioner_msa_name>    (Hub, written by klusterlet)
  └── label: cluster.open-cluster-management.io/backup=cluster             (patched by this role)
```

## Usage

### Via **`acm_dr_spoke_manager`** (recommended)

Set **`acm_dr_spoke_manager_msa_enabled: true`** when running **`action=onboard`**. The spoke_manager calls this role automatically in Phase 4.5.

```bash
ansible-navigator run playbooks/manage-spoke.yml \
  -e acm_dr_spoke_manager_action=onboard \
  -e acm_dr_spoke_manager_cluster_name=aro-spoke-01 \
  -e acm_dr_spoke_manager_msa_enabled=true
```

### Standalone

```bash
ansible-navigator run playbooks/manage-spoke.yml \
  -e acm_dr_spoke_manager_action=msa_provision \
  -e acm_dr_spoke_manager_cluster_name=aro-spoke-01
```

> **Note:** standalone invocation requires a separate playbook entry point or a wrapper playbook that calls the role directly. The **`manage-spoke.yml`** playbook currently invokes **`acm_dr_spoke_manager`**, which dispatches to this role when **`msa_enabled`** is true.

## Consuming the MSA

Once provisioned, the MSA token Secret is available at **`<spoke-name>/ansible-dr-orchestrator-msa`** on the Hub.

**Stage 07b MSA Spoke Verifier** (**`acm_dr_failover_manager`**):

```yaml
# In orchestrate-dr-failover.yml extra-vars:
acm_dr_failover_manager_enable_msa_verification: true
```

**`acm_hub_token_resolver`** (**`infra.support_assist`**):

```yaml
# In the must-gather playbook vars:
acm_hub_token_resolver_msa_name: "ansible-dr-orchestrator-msa"
```

No code changes required in either consumer. the MSA name is the shared contract.

## Idempotency

All Kubernetes objects use **`state: present`**. Re-running against a Spoke that already has the MSA is safe. Kubernetes no-ops on matching objects and the OADP label patch is idempotent.
