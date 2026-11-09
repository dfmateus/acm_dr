# Scripts

Standalone Bash utilities for manual and interactive operations outside Ansible playbooks.
None of these are called from any role; they exist for break-glass, onboarding, and
interactive orchestration workflows.

## Categories

| Directory | Purpose | When to use |
| --- | --- | --- |
| [cluster-onboarding/](cluster-onboarding/) | Register clusters, provision Zero-Trust SAs, build Spoke fleet kubeconfigs | Before a cluster joins the fleet |
| [dr-orchestrator/](dr-orchestrator/) | Interactive failover/failback wrapper | DR events, planned maintenance, readiness drills |
| [break-glass/](break-glass/) | Force-remove stuck finalizers and Terminating namespaces | RHACM leaves residue after a failed detach |
| [deep-cleanup/](deep-cleanup/) | Nuclear-level removal of Observability/GitOps stacks | When the [*`acm_dr_hub_cleanup`*](../roles/acm_dr_hub_cleanup) role cannot recover corrupted state |
| [lib/](lib/) | Sourced helpers (not standalone scripts) | Called by other scripts in this tree |
| [testing/](testing/) | Offline compliance report rendering and validation | Before any change to the Jinja2 report template |

## Compliance report testing (testing/)

The **`testing/`** directory contains an offline test suite for the Jinja2 compliance report template used by **`acm_dr_failover_manager`** Stage 08. It runs without any cluster access and catches template syntax errors, missing **`default()`** filters, and layout regressions before they reach a live execution.

### When to run

Run this test suite before committing any change to [*`roles/acm_dr_failover_manager/templates/reports/dr_compliance_report.j2`*](../roles/acm_dr_failover_manager/templates/reports/dr_compliance_report.j2). It is also appropriate to run it after updating any variable that appears in the report template.

### How to run

The test is a two-step process:

```bash
# Step 1: render the template against each mock scenario
# Output goes to testing/rendered_reports/<scenario>.txt (generated directory, not committed)
ansible-playbook examples/scripts/testing/render_compliance_reports.yml

# Step 2: assert expected patterns in the rendered output
# Exits 0 if all assertions pass, 1 if any assertion fails
bash examples/scripts/testing/validate_rendered_reports.sh
```

Both commands run from the repository root.

### Mock scenarios

Each file in **`testing/mock_data/`** overrides the **`_base.yml`** variable set to simulate a different operational state. The base file provides common variables shared by all scenarios.

| Scenario file | What it simulates |
| --- | --- |
| **`_base.yml`** | Common variable base, included first by every scenario |
| **`all_green.yml`** | All checks pass, all Spokes healthy, all policies compliant |
| **`split_brain.yml`** | Both Hubs appear active simultaneously (BackupSchedule not paused on source) |
| **`degraded_addons.yml`** | One or more ACM add-ons on Spokes in **`Available=False`** state |
| **`dry_run.yml`** | Pipeline ran in dry-run mode. Report shows **`DRY-RUN`** markers throughout. |
| **`everything_broken.yml`** | All checks fail simultaneously (worst-case rendering stress test) |
| **`multi_hub.yml`** | Multi-Hub topology with more than two Hubs in the DR pair |
| **`unreachable_spokes.yml`** | Some Spokes did not respond during the postflight check |
| **`version_skew.yml`** | Hub and Spoke RHACM/OCP versions outside the supported compatibility matrix |

### Output directory

**`testing/rendered_reports/`** is generated at test time and is not committed to the repository. It appears after the first run of **`render_compliance_reports.yml`** and can be inspected manually to verify report content and formatting.

## Shared helper

[*`load_cluster_env.sh`*](lib/load_cluster_env.sh) maps per-cluster **`.env`** files
(**`~/.kube/clusters/<context>.env`**) to role-prefixed environment variables
(**`ACM_DR_SOURCE_*`**, **`ACM_DR_DEST_*`**, **`ACM_DR_TARGET_*`**, **`ACM_DR_SPOKE_*`**). It must be
**sourced**, not executed. See [cluster-onboarding/](cluster-onboarding/) for details.

## Prerequisites

All scripts expect **`oc`** (and some expect **`jq`**, **`kubectl`**, **`ansible-playbook`**) in **`PATH`**.
Each script checks its own prerequisites at startup and fails with a clear message if
something is missing.

## Migration reference

Scripts were reorganized from a flat **`scripts/`** directory. This table maps old names to
new locations:

| Old name | New location |
| --- | --- |
| **`register_new_cluster.sh`** | [*`01_register_cluster.sh`*](cluster-onboarding/01_register_cluster.sh) |
| **`provision_automation_sa.sh`** | [*`02_provision_automation_sa.sh`*](cluster-onboarding/02_provision_automation_sa.sh) |
| **`run_dr_orchestrator.sh`** | [*`run_failover.sh`*](dr-orchestrator/run_failover.sh) |
| **`force_purge_hub_spoke.sh`** | [*`force_purge_managed_cluster.sh`*](break-glass/force_purge_managed_cluster.sh) |
| **`force_delete_namespace.sh`** | [*`force_delete_namespace.sh`*](break-glass/force_delete_namespace.sh) |
| **`purge_acm_observability.sh`** | [*`purge_acm_observability.sh`*](deep-cleanup/purge_acm_observability.sh) |
| **`purge_gitops.sh`** | [*`purge_gitops.sh`*](deep-cleanup/purge_gitops.sh) |
| *(new)* | [*`03_build_spoke_fleet.sh`*](cluster-onboarding/03_build_spoke_fleet.sh) |
| *(new)* | [*`load_cluster_env.sh`*](lib/load_cluster_env.sh) |
