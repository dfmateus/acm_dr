# DR Orchestrator

Interactive wrapper around the
[*`orchestrate-dr-failover.yml`*](../../playbooks/orchestrate-dr-failover.yml) playbook.
Validates prerequisites, confirms the direction with the operator, and runs the playbook
with the selected parameters.

## Script

[*`run_failover.sh`*](run_failover.sh)

```bash
# Run from the project root:
./examples/scripts/dr-orchestrator/run_failover.sh
```

The script prompts for every required parameter. Dry-run is the default when you press
ENTER at the execution-mode prompt; production mode requires an explicit **`n`**.

## Scenarios

| Scenario | What it does |
| --- | --- |
| **Hub Switchover** | Fails the fleet over from the failed Hub to the standby Hub. Full 9-stage pipeline (preflight through postflight compliance report). |
| **Planned Maintenance** | Fails the fleet to the standby Hub so the primary can be upgraded with zero downtime. After the upgrade, run it again in the reverse direction to fail back. |
| **DR Readiness Drill** | Runs the entire pipeline in dry-run mode (**`acm_dr_failover_manager_dry_run=true`**) against real clusters. Safety assertions execute at full strength; only mutating steps are replaced with **`🔎 [DRY-RUN]`** messages. |

## Credential modes

The script supports two ways to authenticate against the source and destination Hubs:

1. **Per-cluster credentials** (primary): picks **`.env`** files from **`~/.kube/clusters/`**
   interactively, or uses **`ACM_DR_SOURCE_*`** / **`ACM_DR_DEST_*`** environment variables if
   already loaded via [*`load_cluster_env.sh`*](../lib/load_cluster_env.sh).

2. **Monolithic kubeconfig** (legacy): picks `*-sa` contexts from the local **`KUBECONFIG`**
   file.

## Prerequisites

- **`oc`**, **`ansible-playbook`**, **`curl`** in **`PATH`**
- Run from the project root (the script looks for
  **`playbooks/orchestrate-dr-failover.yml`** relative to **`pwd`**)
- Hub ServiceAccount contexts provisioned via
  [*`02_provision_automation_sa.sh`*](../cluster-onboarding/02_provision_automation_sa.sh)
