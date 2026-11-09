# Deep Cleanup

Aggressive, full-stack removal of the RHACM Observability (Thanos) and OpenShift GitOps
(ArgoCD) ecosystems. These scripts strip finalizers, delete CRDs, remove OLM
subscriptions/CSVs, and force-delete namespaces, leaving no trace of the stack behind.

## How this differs from the Ansible role

The [*`acm_dr_hub_cleanup`*](../../roles/acm_dr_hub_cleanup) role performs **scoped,
idempotent removal** of DR-specific configuration while preserving the base operators and
Azure backup data. It is the right tool for normal decommissioning.

These scripts exist for situations the role cannot recover from: corrupted operator state,
orphaned CRDs blocking re-installation, finalizers stuck in a loop, or a cluster where
partial manual cleanup left the stack in an inconsistent state that the role's idempotent
checks cannot reconcile.

## Scripts

### Purge RHACM Observability

[*`purge_acm_observability.sh`*](purge_acm_observability.sh)

Removes the **`MultiClusterObservability`** CR, the **`thanos-object-storage`** secret, the
Observability operator subscription/CSV, and the
**`open-cluster-management-observability`** namespace.

```bash
# Default context (acm-primary-hub):
./examples/scripts/deep-cleanup/purge_acm_observability.sh

# Explicit context:
./examples/scripts/deep-cleanup/purge_acm_observability.sh acm-dr-hub-sa
```

### Purge OpenShift GitOps

[*`purge_gitops.sh`*](purge_gitops.sh)

Removes all ArgoCD **`Application`**, **`ApplicationSet`**, **`AppProject`**, and **`ArgoCD`** CRs across
every namespace (stripping finalizers first), then removes the GitOps operator
subscription/CSV, CRDs, and all GitOps-related namespaces.

```bash
# Default namespaces (openshift-gitops-operator, openshift-gitops, etc.):
./examples/scripts/deep-cleanup/purge_gitops.sh

# Custom namespace list:
./examples/scripts/deep-cleanup/purge_gitops.sh "openshift-gitops-operator openshift-gitops my-argocd-ns"
```

## Prerequisites

- **`oc`** and **`jq`** in **`PATH`**
- cluster-admin context on the target cluster

## Risk

These are destructive, non-reversible operations. They remove operators, CRDs, and all
associated data. There is no undo. Run the
[*`acm_dr_hub_cleanup`*](../../roles/acm_dr_hub_cleanup) role first; use these scripts only
when the role fails or the operator state is too corrupted for it to converge.
