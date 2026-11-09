# Break-Glass Operations

Emergency tools for recovering from stuck Kubernetes state that normal Ansible playbooks
and **`oc delete`** cannot resolve. These are not day-to-day utilities; reach for them only
when RHACM leaves residue that blocks further operations.

## When to use

After a failed Spoke detach or a partially completed DR failover, RHACM can leave
**`ManagedCluster`** objects and namespaces stuck in **`Terminating`** state due to orphaned
finalizers that the operator will never clear on its own. The standard Spoke detach
procedure is documented in
[KCS 5950901](https://access.redhat.com/solutions/5950901);
these scripts handle the cases where that procedure was interrupted or failed partway
through.

## Scripts

### Force-purge stuck ManagedCluster objects

[*`force_purge_managed_cluster.sh`*](force_purge_managed_cluster.sh)

Strips finalizers from **`ManagedCluster`** objects and their associated namespaces on a Hub
cluster. Accepts the Hub context and a list of cluster names (interactive or via CLI
arguments).

```bash
# Interactive (prompts for context and cluster names):
./examples/scripts/break-glass/force_purge_managed_cluster.sh

# Non-interactive:
./examples/scripts/break-glass/force_purge_managed_cluster.sh acm-dr-hub-sa spoke-01,spoke-02
```

### Force-delete Terminating namespaces

[*`force_delete_namespace.sh`*](force_delete_namespace.sh)

Clears the **`spec.finalizers`** array via a raw **`PUT`** to the **`/finalize`** API endpoint.
Idempotent: exits cleanly if the namespace is already gone.

```bash
./examples/scripts/break-glass/force_delete_namespace.sh my-stuck-namespace
```

## Prerequisites

- **`oc`** and **`jq`** in **`PATH`**
- An active kubeconfig context with cluster-admin privileges on the target cluster

## Risk

These scripts bypass Kubernetes finalizer contracts. Resources that the finalizer would
have cleaned up (agent namespaces on Spoke clusters, external cloud resources) may become
orphaned. Verify the Spoke-side state after running these and clean up manually if needed.
