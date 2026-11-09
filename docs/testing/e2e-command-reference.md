# E2E command reference

Complete **`ansible-playbook`** commands for every test scenario in the [E2E validation matrix](e2e-validation-matrix.md). Each command is ready to copy-paste after sourcing the environment.

## Test case index

<!-- markdownlint-disable MD051 -->

| ID | Test case | Phase |
|----|-----------|-------|
| [TC-01.1](#tc-011--setup-hub-01-as-primary-active-leader) | Setup Hub-01 as PRIMARY (active leader) | [Phase 1](#phase-1-lab-setup-and-topology-detection) |
| [TC-01.3](#tc-013--setup-hub-02-as-passive) | Setup Hub-02 as PASSIVE | [Phase 1](#phase-1-lab-setup-and-topology-detection) |
| [TC-01.6](#tc-016--idempotent-re-provision-on-hub-01-force-flag) | Idempotent re-provision on Hub-01 (force flag) | [Phase 1](#phase-1-lab-setup-and-topology-detection) |
| [TC-01.7](#tc-017--hub-type-mismatch-guard) | Hub type mismatch guard | [Phase 1](#phase-1-lab-setup-and-topology-detection) |
| [TC-02.1](#tc-021--onboard-aro-classic-spoke-ocp-auto-detect) | Onboard ARO Classic Spoke (OCP, auto-detect) | [Phase 2](#phase-2-spoke-onboarding) |
| [TC-02.4](#tc-024--onboard-aks-spoke-non-ocp-manual-labels) | Onboard AKS Spoke (non-OCP, manual labels) | [Phase 2](#phase-2-spoke-onboarding) |
| [TC-02.6](#tc-026--onboard-eks-spoke-cross-cloud-aws-to-azure) | Onboard EKS Spoke (cross-cloud, AWS to Azure) | [Phase 2](#phase-2-spoke-onboarding) |
| [TC-02.8](#tc-028--onboard-aro-hcp-spoke-ocp-cross-region) | Onboard ARO HCP Spoke (OCP, cross-region) | [Phase 2](#phase-2-spoke-onboarding) |
| [TC-03.1](#tc-031--dry-run-failover-hub-01-to-hub-02) | Dry-run failover Hub-01 to Hub-02 | [Phase 3](#phase-3-dr-failover-standard) |
| [TC-03.5](#tc-035--production-failover-hub-01-to-hub-02) | Production failover Hub-01 to Hub-02 | [Phase 3](#phase-3-dr-failover-standard) |
| [TC-03.14](#tc-0314--dry-run-failback-hub-02-to-hub-01) | Dry-run failback Hub-02 to Hub-01 | [Phase 3](#phase-3-dr-failover-standard) |
| [TC-03.15](#tc-0315--production-failback-hub-02-to-hub-01) | Production failback Hub-02 to Hub-01 | [Phase 3](#phase-3-dr-failover-standard) |
| [TC-03.16 to TC-03.22](#failback-verifications-tc-0316-to-tc-0322) | Failback verifications | [Phase 3](#phase-3-dr-failover-standard) |
| [TC-04.1](#tc-041--failover-hub-01-to-hub-02-free-hub-01-for-upgrade) | Failover Hub-01 to Hub-02 (free Hub-01 for upgrade) | [Phase 4](#phase-4-planned-maintenance-failover-with-acm-upgrade) |
| [TC-04.2](#tc-042--upgrade-acm-on-idle-hub-01-213-to-215) | Upgrade ACM on idle Hub-01 (2.13 to 2.15) | [Phase 4](#phase-4-planned-maintenance-failover-with-acm-upgrade) |
| [TC-04.3](#tc-043--dry-run-failback-with-target-version-validation) | Dry-run failback with target version validation | [Phase 4](#phase-4-planned-maintenance-failover-with-acm-upgrade) |
| [TC-04.4](#tc-044--production-failback-hub-02-to-hub-01-upgraded-to-acm-215) | Production failback Hub-02 to Hub-01 (upgraded) | [Phase 4](#phase-4-planned-maintenance-failover-with-acm-upgrade) |
| [TC-04.6](#tc-046--backward-restore-gate-negative-test) | Backward restore gate (negative test) | [Phase 4](#phase-4-planned-maintenance-failover-with-acm-upgrade) |
| [TC-04.7](#tc-047--upgrade-hub-02-to-acm-215-symmetric-pair) | Upgrade Hub-02 to ACM 2.15 (symmetric pair) | [Phase 4](#phase-4-planned-maintenance-failover-with-acm-upgrade) |
| [TC-05.1](#tc-051--full-dry-run-drill-hub-01-to-hub-02) | Full dry-run drill Hub-01 to Hub-02 | [Phase 5](#phase-5-dr-readiness-drill) |
| [TC-06.1](#tc-061--reversed-direction-guard) | Reversed direction guard | [Phase 6](#phase-6-edge-cases-and-negative-tests) |
| [TC-06.2](#tc-062--override-reversed-direction-guard) | Override reversed direction guard | [Phase 6](#phase-6-edge-cases-and-negative-tests) |
| [TC-06.3](#tc-063--active-hub-cleanup-protection) | Active Hub cleanup protection | [Phase 6](#phase-6-edge-cases-and-negative-tests) |
| [TC-06.4](#tc-064--cleanup-force-override) | Cleanup force override | [Phase 6](#phase-6-edge-cases-and-negative-tests) |
| [TC-06.5](#tc-065--topology-gate-on-setup) | Topology gate on setup | [Phase 6](#phase-6-edge-cases-and-negative-tests) |
| [TC-06.6](#tc-066--missing-kubeconfig-context) | Missing KUBECONFIG context | [Phase 6](#phase-6-edge-cases-and-negative-tests) |
| [TC-07.1](#tc-071--dry-run-cleanup-on-hub-02) | Dry-run cleanup on Hub-02 | [Phase 7](#phase-7-cleanup-and-decommission) |
| [TC-07.2](#tc-072--production-cleanup-on-hub-02) | Production cleanup on Hub-02 | [Phase 7](#phase-7-cleanup-and-decommission) |
| [TC-07.4](#tc-074--cross-hub-storage-dependency-warning) | Cross-hub storage dependency warning | [Phase 7](#phase-7-cleanup-and-decommission) |
| [TC-07.5](#tc-075--cleanup-confirmation-gate) | Cleanup confirmation gate | [Phase 7](#phase-7-cleanup-and-decommission) |
| [TC-08.2](#tc-082--re-setup-hub-02-as-passive) | Re-setup Hub-02 as passive | [Phase 8](#phase-8-multi-hub-topology-3-hub) |
| [TC-08.3](#tc-083--setup-hub-03-as-passive) | Setup Hub-03 as passive | [Phase 8](#phase-8-multi-hub-topology-3-hub) |
| [TC-08.6](#tc-086--failover-hub-01-to-hub-02-with-additional-passive-hub) | Failover Hub-01 to Hub-02 with additional passive hub | [Phase 8](#phase-8-multi-hub-topology-3-hub) |
| [TC-08.10](#tc-0810--failback-hub-02-to-hub-01-with-additional-passive-hub) | Failback Hub-02 to Hub-01 with additional passive hub | [Phase 8](#phase-8-multi-hub-topology-3-hub) |
| [TC-08.12](#tc-0812--skip-passive-recycling-flag) | Skip passive recycling flag | [Phase 8](#phase-8-multi-hub-topology-3-hub) |
| [TC-09.1](#tc-091--graceful-spoke-detach-aro-classic-spoke-01) | Graceful Spoke detach (aro-classic-spoke-01) | [Phase 9](#phase-9-spoke-lifecycle) |
| [TC-09.3](#tc-093--re-onboard-same-spoke-aro-classic-spoke-01) | Re-onboard same Spoke (aro-classic-spoke-01) | [Phase 9](#phase-9-spoke-lifecycle) |
| [TC-09.4](#tc-094--detach-idempotency) | Detach idempotency | [Phase 9](#phase-9-spoke-lifecycle) |
| [TC-10.1](#tc-101--create-parametric-argocd-instance) | Create parametric ArgoCD instance | [Phase 10](#phase-10-argocd-instance-management) |
| [TC-10.3](#tc-103--cleanup-argocd-instance) | Cleanup ArgoCD instance | [Phase 10](#phase-10-argocd-instance-management) |
| [TC-11.1](#tc-111--dr-readiness-check-both-hubs) | DR readiness check (both Hubs) | [Phase 11](#phase-11-dr-readiness-check) |
| [TC-11.2](#tc-112-readiness-check---rpo-threshold-violation) | Readiness check - RPO threshold violation | [Phase 11](#phase-11-dr-readiness-check) |
| [TC-12.1](#tc-121-wf-01-approval-denial-path) | WF-01 approval denial path | [Phase 12](#phase-12-wf-01-failure-path-approval-denial) |
| [TC-12.2](#tc-122-wf-01-approval-timeout-path) | WF-01 approval timeout path | [Phase 12](#phase-12-wf-01-failure-path-approval-denial) |

<!-- markdownlint-enable MD051 -->

## Parameter glossary

| Parameter | Playbook(s) | Purpose |
|-----------|-------------|---------|
| **`-e k8s_target_context=<ctx>`** | All | Kubeconfig context of the target Hub cluster. Always the `*-sa` (ServiceAccount) context |
| **`-e is_primary_hub=true\|false`** | **`setup-acm-dr-hub.yml`** | **`true`** creates BackupSchedule (active leader). **`false`** creates passive sync Restore CR |
| **`-e acm_dr_hub_setup_mch_channel=release-X.Y`** | **`setup-acm-dr-hub.yml`** | ACM operator channel. Overrides the default (**`release-2.14`**). Controls which ACM version OLM installs |
| **`-e acm_dr_hub_setup_azure_storage_allow_reuse=true`** | **`setup-acm-dr-hub.yml`** | Bypass the safety lock when the Azure Storage Account already exists (created by the first Hub) |
| **`-e acm_dr_hub_setup_allow_existing_dr=true`** | **`setup-acm-dr-hub.yml`** | Bypass the "EXISTING DR TOPOLOGY DETECTED" gate for idempotent re-provisioning |
| **`-e failover_direction=<source>_to_<dest>`** | **`orchestrate-dr-failover.yml`** | Failover direction. Format: **`<source-ctx>_to_<destination-ctx>`** using `*-sa` context names |
| **`-e acm_dr_failover_manager_dry_run=true`** | **`orchestrate-dr-failover.yml`** | Run the entire pipeline in **`check_mode`**. No real mutations. Safety assertions still evaluate |
| **`-e skip_gates=true`** | **`orchestrate-dr-failover.yml`** | Skip the manual confirmation gate at Stage 01. Required for non-interactive execution |
| **`-e acm_dr_failover_manager_skip_version_gate=true`** | **`orchestrate-dr-failover.yml`** | Bypass fleet compatibility gate when Spoke OCP versions fall outside the destination ACM supported range |
| **`-e acm_dr_failover_manager_target_acm_version=X.Y`** | **`orchestrate-dr-failover.yml`** | Declare the target ACM version for Planned Maintenance Switchover validation |
| **`-e acm_dr_failover_manager_allow_fenced_origin=true`** | **`orchestrate-dr-failover.yml`** | Bypass the reversed-direction guard when the source Hub is already fenced (BackupSchedule paused) |
| **`-e acm_dr_failover_manager_additional_passive_hubs='["ctx1","ctx2"]'`** | **`orchestrate-dr-failover.yml`** | List of additional passive Hub contexts for multi-hub Restore recycling (Stage 06a) |
| **`-e acm_dr_failover_manager_skip_passive_recycling=true`** | **`orchestrate-dr-failover.yml`** | Skip Stage 06a passive sync Restore recycling entirely |
| **`-e acm_dr_spoke_manager_action=prep\|detach`** | **`manage-spoke.yml`** | Spoke lifecycle action. **`prep`** onboards, **`detach`** removes. Default: **`prep`** |
| **`-e acm_dr_spoke_manager_cluster_name=<name>`** | **`manage-spoke.yml`** | Name of the ManagedCluster object in RHACM |
| **`-e acm_dr_spoke_manager_spoke_k8s_context=<ctx>`** | **`manage-spoke.yml`** | Kubeconfig context of the Spoke cluster (`*-sa` context) |
| **`-e acm_dr_spoke_manager_cluster_cloud=<cloud>`** | **`manage-spoke.yml`** | ManagedCluster cloud label. For OCP Spokes this is auto-detected via **`Infrastructure`** CR. For non-OCP use **`Azure`**, **`Amazon`**, **`Google`**, etc. Vendor is auto-detected for all Spokes (**`OpenShift`** or **`Kubernetes`**) |
| **`--tags spoke_prep\|spoke_detach`** | **`manage-spoke.yml`** | Tag filter selecting which task file to load. Use **`spoke_prep`** with **`action=prep`**, **`spoke_detach`** with **`action=detach`** |
| **`-e acm_dr_hub_cleanup_confirm=true`** | **`cleanup-acm-dr-hub.yml`** | Mandatory confirmation gate. Without it, cleanup refuses to run |
| **`-e acm_dr_hub_cleanup_dry_run=true`** | **`cleanup-acm-dr-hub.yml`** | Run cleanup in **`check_mode`**. Shows what would be removed without applying |
| **`-e acm_dr_hub_cleanup_force=true`** | **`cleanup-acm-dr-hub.yml`** | Override the "Hub looks ACTIVE" safety guard (BackupSchedule present and unpaused) |
| **`-e acm_dr_hub_cleanup_purge_azure_storage=true`** | **`cleanup-acm-dr-hub.yml`** | Also remove Azure Storage Account and Blob containers (preserved by default) |
| **`-e acm_dr_hub_cleanup_known_peer_hubs='["ctx1"]'`** | **`cleanup-acm-dr-hub.yml`** | List of peer Hub contexts to check for active BSL before purging storage |
| **`-e acm_argocd_instance_cleanup_confirm=true`** | **`cleanup-argocd-instance.yml`** | Mandatory confirmation for ArgoCD instance removal |
| **`-e acm_dr_hub_setup_debug_no_log=false`** | **`setup-acm-dr-hub.yml`** | Expose **`no_log`** task output (tokens, secrets) for troubleshooting. Default: **`true`** (hidden). See [Debugging tips](#debugging-tips) |
| **`-e acm_dr_failover_manager_debug_no_log=false`** | **`orchestrate-dr-failover.yml`** | Same as above, scoped to the failover manager role |
| **`-e acm_dr_spoke_manager_debug_no_log=false`** | **`manage-spoke.yml`** | Same as above, scoped to the spoke manager role |
| **`-e acm_dr_hub_cleanup_debug_no_log=false`** | **`cleanup-acm-dr-hub.yml`** | Same as above, scoped to the lab cleanup role |
| **`-e acm_argocd_instance_setup_debug_no_log=false`** | **`manage-argocd-instance.yml`** | Same as above, scoped to the ArgoCD instance setup role |
| **`-e acm_dr_kubeconfig_resolver_debug_no_log=false`** | All (pre_tasks) | Same as above, scoped to the kubeconfig resolver (exposes assembled tokens) |
| **`-v`** | All | Ansible verbosity. Use **`-vv`** or **`-vvv`** for deeper debugging |

---

## Debugging tips

### Exposing **`no_log`** task output

All tasks that handle sensitive data (tokens, client secrets, kubeconfig content) suppress their output with **`no_log`**. When a job fails inside one of these tasks, the error message shows **`"censored"`** instead of the actual value, which makes troubleshooting difficult.

Each role has its own `*_debug_no_log` variable (default **`true`**). Set it to **`false`** to reveal the hidden output for that role only, without affecting other roles in the same run.

```bash
# Reveal hidden output for Lab Setup only
ansible-playbook playbooks/setup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e is_primary_hub=true \
  -e acm_dr_hub_setup_debug_no_log=false \
  -v
```

```bash
# Reveal hidden output for the kubeconfig resolver (assembled tokens)
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-01-sa_to_acmdr-hub-02-sa \
  -e acm_dr_failover_manager_dry_run=true \
  -e acm_dr_kubeconfig_resolver_debug_no_log=false \
  -e skip_gates=true \
  -v
```

| Role | Variable | Scope |
|------|----------|-------|
| **`acm_dr_hub_setup`** | **`acm_dr_hub_setup_debug_no_log`** | Azure creds, GitHub PAT, kubeconfig, pull secrets |
| **`acm_dr_failover_manager`** | **`acm_dr_failover_manager_debug_no_log`** | Hub connectivity tokens, Spoke bootstrap secrets |
| **`acm_dr_spoke_manager`** | **`acm_dr_spoke_manager_debug_no_log`** | Spoke SA tokens, auto-import secrets |
| **`acm_dr_hub_cleanup`** | **`acm_dr_hub_cleanup_debug_no_log`** | Azure CLI credentials, storage keys |
| **`acm_dr_kubeconfig_resolver`** | **`acm_dr_kubeconfig_resolver_debug_no_log`** | Assembled runtime kubeconfig (all bearer tokens) |
| **`acm_argocd_instance_setup`** | **`acm_argocd_instance_setup_debug_no_log`** | Git repo credentials |

On AAP, these variables are pre-configured in each Job Template's extra vars as **`true`**. To debug a failing job, edit the JT extra vars and change **`true`** to **`false`**, then re-launch. Change it back after troubleshooting.

⚠️ **Security reminder:** with **`debug_no_log=false`**, bearer tokens and credentials appear in plain text in the job stdout. On AAP, any user with read access to the job can see them. Always set it back to **`true`** after troubleshooting.

---

## Phase 1: Lab setup and topology detection

Provision the RHACM DR infrastructure on Hub clusters. Hub-01 becomes the active leader (creates **`BackupSchedule`**). Hub-02 becomes passive (creates passive sync **`Restore`** CR). Both share the same Azure Storage Account for OADP backups.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

### TC-01.1: Setup Hub-01 as PRIMARY (active leader)

Creates: Azure Storage, MCH, Observability, GitOps/ArgoCD, OADP/DPA, BackupSchedule.

```bash
ansible-playbook playbooks/setup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e is_primary_hub=true \
  -e acm_dr_hub_setup_mch_channel=release-2.13 \
  -v
```

### TC-01.3: Setup Hub-02 as PASSIVE

Same pipeline as TC-01.1, but creates passive sync Restore instead of BackupSchedule. **`azure_storage_allow_reuse=true`** because Hub-01 already created the Storage Account.

```bash
ansible-playbook playbooks/setup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-02-sa \
  -e is_primary_hub=false \
  -e acm_dr_hub_setup_mch_channel=release-2.13 \
  -e acm_dr_hub_setup_azure_storage_allow_reuse=true \
  -v
```

### TC-01.6: Idempotent re-provision on Hub-01 (force flag)

After initial setup, the topology gate blocks re-runs. **`allow_existing_dr=true`** bypasses it.

```bash
ansible-playbook playbooks/setup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e is_primary_hub=true \
  -e acm_dr_hub_setup_mch_channel=release-2.13 \
  -e acm_dr_hub_setup_azure_storage_allow_reuse=true \
  -e acm_dr_hub_setup_allow_existing_dr=true \
  -v
```

### TC-01.7: Hub type mismatch guard

Declaring Hub-02 (detected as PASSIVE) as **`is_primary_hub=true`** triggers a blocking topology guard assert: "declared PRIMARY but detected PASSIVE". Requires **`acm_dr_hub_setup_allow_existing_dr=true`** to proceed.

```bash
ansible-playbook playbooks/setup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-02-sa \
  -e is_primary_hub=true \
  -e acm_dr_hub_setup_mch_channel=release-2.13 \
  -e acm_dr_hub_setup_azure_storage_allow_reuse=true \
  -e acm_dr_hub_setup_allow_existing_dr=true \
  -v
```

---

## Phase 2: Spoke onboarding

Onboard Spoke (Managed) clusters to the active Hub. OCP Spokes (ARO Classic, ARO HCP) auto-detect **`vendor`** and **`cloud`** labels from the **`Infrastructure`** CR. Non-OCP Spokes (AKS, EKS) require explicit **`-e`** overrides for these labels.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

### TC-02.1: Onboard ARO Classic Spoke (OCP, auto-detect)

OCP Spoke: vendor and cloud labels are auto-detected from the Infrastructure CR.

```bash
ansible-playbook playbooks/manage-spoke.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e acm_dr_spoke_manager_action=prep \
  -e acm_dr_spoke_manager_cluster_name=aro-classic-spoke-01 \
  -e acm_dr_spoke_manager_spoke_k8s_context=aro-classic-spoke-01-sa \
  --tags spoke_prep \
  -v
```

### TC-02.4: Onboard AKS Spoke (non-OCP, cloud label via extra-var)

Vendor is auto-detected as **`Kubernetes`** (no Infrastructure CR on AKS). Only **`cluster_cloud=Azure`** needs to be passed. The correct variable is **`acm_dr_spoke_manager_cluster_cloud`**, NOT **`acm_dr_spoke_manager_cloud`** (which does not exist).

```bash
ansible-playbook playbooks/manage-spoke.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e acm_dr_spoke_manager_action=prep \
  -e acm_dr_spoke_manager_cluster_name=aks-spoke-01 \
  -e acm_dr_spoke_manager_spoke_k8s_context=aks-spoke-01-sa \
  -e acm_dr_spoke_manager_cluster_cloud=Azure \
  --tags spoke_prep \
  -v
```

### TC-02.6: Onboard EKS Spoke (cross-cloud, AWS to Azure)

Same non-OCP path as AKS, but **`cluster_cloud=Amazon`** for the AWS cloud label. Vendor is auto-detected as **`Kubernetes`**.

```bash
ansible-playbook playbooks/manage-spoke.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e acm_dr_spoke_manager_action=prep \
  -e acm_dr_spoke_manager_cluster_name=eks-spoke-01 \
  -e acm_dr_spoke_manager_spoke_k8s_context=eks-spoke-01-sa \
  -e acm_dr_spoke_manager_cluster_cloud=Amazon \
  --tags spoke_prep \
  -v
```

### TC-02.8: Onboard ARO HCP Spoke (OCP, cross-region)

Cross-region onboarding: canadacentral Spoke joins eastus Hub. Vendor and cloud auto-detected from Infrastructure CR.

```bash
ansible-playbook playbooks/manage-spoke.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e acm_dr_spoke_manager_action=prep \
  -e acm_dr_spoke_manager_cluster_name=aro-hcp-spoke-01 \
  -e acm_dr_spoke_manager_spoke_k8s_context=aro-hcp-spoke-01-sa \
  --tags spoke_prep \
  -v
```

---

## Phase 3: DR failover (standard)

Full DR round-trip at the same ACM/OCP version. Dry-run validates the failover pipeline, then production failover moves the fleet from Hub-01 to Hub-02. After verifying the failover, the same pipeline runs in reverse (dry-run then production failback) to return the fleet to Hub-01.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

### 3a. Dry-run failover

#### TC-03.1: Dry-run failover Hub-01 to Hub-02

**`skip_gates=true`**: skip manual confirmation (Stage 01) for non-interactive execution. **`skip_version_gate=true`**: bypass fleet compatibility gate because aro-classic-spoke-01/aro-hcp-spoke-01 (OCP 4.20) are outside ACM 2.13's supported range (4.16-4.19). This is expected in a mixed-version lab; the gate correctly fires but can be overridden.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-01-sa_to_acmdr-hub-02-sa \
  -e acm_dr_failover_manager_dry_run=true \
  -e skip_gates=true \
  -e acm_dr_failover_manager_skip_version_gate=true \
  -v
```

### 3b. Production failover

#### TC-03.5: Production failover Hub-01 to Hub-02

Same flags as TC-03.1 minus **`dry_run`**. This is the real failover that pauses BackupSchedule on Hub-01 (logical fencing), resolves explicit backup names by Hub-01's ClusterID, creates OADP Restore CR on Hub-02, sanitizes ManagedServiceAccount tokens ([KCS 7039710](https://access.redhat.com/solutions/7039710)), verifies all Spokes reconnect to Hub-02, creates BackupSchedule on Hub-02 (new leader), detaches old ManagedCluster objects from Hub-01, and runs postflight compliance report.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-01-sa_to_acmdr-hub-02-sa \
  -e skip_gates=true \
  -e acm_dr_failover_manager_skip_version_gate=true \
  -v
```

### 3c. Dry-run failback

#### TC-03.14: Dry-run failback Hub-02 to Hub-01

Validates the reverse direction works without mutations.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-02-sa_to_acmdr-hub-01-sa \
  -e acm_dr_failover_manager_dry_run=true \
  -e skip_gates=true \
  -e acm_dr_failover_manager_skip_version_gate=true \
  -v
```

### 3d. Production failback

#### TC-03.15: Production failback Hub-02 to Hub-01

Round-trip completion: fleet returns to Hub-01. Same 8-stage pipeline in reverse: fence Hub-02, restore on Hub-01, sanitize, verify Spokes, create BackupSchedule, detach Hub-02, compliance report.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-02-sa_to_acmdr-hub-01-sa \
  -e skip_gates=true \
  -e acm_dr_failover_manager_skip_version_gate=true \
  -v
```

### Failback verifications (TC-03.16 to TC-03.22)

| ID | Verification | Command |
|----|--------------|---------|
| TC-03.16 | Hub-02 BackupSchedule paused | **`oc get backupschedule schedule-acm-hub -n open-cluster-management-backup --context acmdr-hub-02-sa -o jsonpath='{.spec.paused}'`** |
| TC-03.17 | Backup resolution by Hub-02 ClusterID | Check TC-03.15 output for "Resolved backup" messages |
| TC-03.18 | [KCS 7039710](https://access.redhat.com/solutions/7039710) sanitization | Check TC-03.15 output for sanitization messages |
| TC-03.19 | Spokes JOINED+AVAILABLE on Hub-01 | **`oc get managedclusters --context acmdr-hub-01-sa`** |
| TC-03.20 | BackupSchedule on Hub-01 | **`oc get backupschedule -n open-cluster-management-backup --context acmdr-hub-01-sa`** |
| TC-03.21 | Hub-02 only local-cluster | **`oc get managedclusters --context acmdr-hub-02-sa`** |
| TC-03.22 | Compliance report clean | Check TC-03.15 final output |

End state Phase 3: Hub-01 active (ACM 2.13, BackupSchedule active, 4 Spokes), Hub-02 idle (ACM 2.13, BackupSchedule paused, only local-cluster).

---

## Phase 4: Planned Maintenance Switchover with ACM upgrade

Zero-downtime Hub upgrade pattern. After Phase 3 round-trip, Hub-01 is active (ACM 2.13) and Hub-02 is idle. The fleet is failed over to Hub-02 to free Hub-01 for upgrade, ACM is upgraded on the idle Hub-01 (2.13 to 2.15), then the fleet is failed back to the upgraded Hub.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

### 4a. Failover (free Hub-01 for upgrade)

#### TC-04.1: Failover Hub-01 to Hub-02 (free Hub-01 for upgrade)

Both Hubs still on ACM 2.13. **`skip_version_gate`** needed because aro-classic-spoke-01/aro-hcp-spoke-01 (OCP 4.20) are outside ACM 2.13's supported range.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-01-sa_to_acmdr-hub-02-sa \
  -e skip_gates=true \
  -e acm_dr_failover_manager_skip_version_gate=true \
  -v
```

### 4b. Upgrade ACM on idle Hub-01

#### TC-04.2: Upgrade ACM on idle Hub-01 (2.13 to 2.15)

Hub-01 is now idle (BackupSchedule paused, no Spokes). Switch the operator channel from **`release-2.13`** to **`release-2.15`**. Wait for MCH to report the new version (15-45 min).

```bash
oc patch subscription.operators.coreos.com advanced-cluster-management \
  -n open-cluster-management \
  --context acmdr-hub-01-sa \
  --type merge \
  -p '{"spec":{"channel":"release-2.15"}}'
```

Monitor the upgrade:

```bash
oc get multiclusterhub multiclusterhub -n open-cluster-management \
  --context acmdr-hub-01-sa \
  -o jsonpath='{.status.currentVersion}{"\n"}'
```

### 4c. Dry-run failback with target version validation

#### TC-04.3: Dry-run failback with target version validation

**`target_acm_version=2.15`** adds preflight checks: ACM 2.15 installed on Hub-01, OCP 4.18 compatible, fleet Spokes in ACM 2.15 supported range (4.18-4.21). **`skip_version_gate`** NOT needed: ACM 2.15 supports OCP 4.20 Spokes.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-02-sa_to_acmdr-hub-01-sa \
  -e acm_dr_failover_manager_target_acm_version=2.15 \
  -e acm_dr_failover_manager_dry_run=true \
  -e skip_gates=true \
  -v
```

### 4d. Production failback (to upgraded Hub-01)

#### TC-04.4: Production failback Hub-02 to Hub-01 (upgraded to ACM 2.15)

Fleet moves to the upgraded Hub-01. Compliance report shows VERSION CHANGE DETECTED.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-02-sa_to_acmdr-hub-01-sa \
  -e acm_dr_failover_manager_target_acm_version=2.15 \
  -e skip_gates=true \
  -v
```

### 4e. Backward restore gate (negative test)

#### TC-04.6: Backward restore gate (negative test)

Hub-01 is now ACM 2.15, Hub-02 still ACM 2.13. Attempting failover TO Hub-02 triggers the backward restore guard. Expected: pipeline blocked.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-01-sa_to_acmdr-hub-02-sa \
  -e acm_dr_failover_manager_dry_run=true \
  -e skip_gates=true \
  -v
```

### 4f. Upgrade Hub-02 (symmetric pair)

#### TC-04.7: Upgrade Hub-02 to ACM 2.15 (symmetric pair)

After the backward restore gate test, upgrade Hub-02 to match Hub-01. Both Hubs on the same ACM version for subsequent phases.

```bash
oc patch subscription.operators.coreos.com advanced-cluster-management \
  -n open-cluster-management \
  --context acmdr-hub-02-sa \
  --type merge \
  -p '{"spec":{"channel":"release-2.15"}}'
```

Monitor the upgrade:

```bash
oc get multiclusterhub multiclusterhub -n open-cluster-management \
  --context acmdr-hub-02-sa \
  -o jsonpath='{.status.currentVersion}{"\n"}'
```

End state Phase 4: Hub-01 active (ACM 2.15), Hub-02 idle (ACM 2.15). Symmetric pair ready for Phase 5+.

---

## Phase 5: DR readiness drill

Dry-run mode used as a rehearsal mechanism against real clusters. Validates that no state mutation occurs. After running, verify that BackupSchedule on Hub-01 is NOT paused, no Restore CR was created on Hub-02, and all Spokes are untouched.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

### TC-05.1: Full dry-run drill Hub-01 to Hub-02

After running, verify: BackupSchedule on Hub-01 is NOT paused (drill did not fence), no Restore CR created on Hub-02, all Spokes untouched.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-01-sa_to_acmdr-hub-02-sa \
  -e acm_dr_failover_manager_dry_run=true \
  -e skip_gates=true \
  -v
```

---

## Phase 6: Edge cases and negative tests

Safety gates and error handling paths that should block dangerous operations.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

### TC-06.1: Reversed direction guard

Attempt failover FROM a Hub whose BackupSchedule is already paused (passive/fenced state). Expected: assert fires "Source Hub BackupSchedule is already PAUSED".

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-01-sa_to_acmdr-hub-02-sa \
  -e skip_gates=true \
  -v
```

### TC-06.2: Override reversed direction guard

Same as TC-06.1 with **`allow_fenced_origin=true`** to bypass the guard. Use case: re-executing an interrupted failover.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-01-sa_to_acmdr-hub-02-sa \
  -e acm_dr_failover_manager_allow_fenced_origin=true \
  -e skip_gates=true \
  -v
```

### TC-06.3: Active Hub cleanup protection

Cleanup on a Hub that has an active (unpaused) BackupSchedule. Expected: assert fires "BackupSchedule PRESENT and NOT PAUSED".

```bash
ansible-playbook playbooks/cleanup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e acm_dr_hub_cleanup_confirm=true \
  -v
```

### TC-06.4: Cleanup force override

Same as TC-06.3 with **`force=true`** to bypass the active Hub guard.

```bash
ansible-playbook playbooks/cleanup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e acm_dr_hub_cleanup_confirm=true \
  -e acm_dr_hub_cleanup_force=true \
  -v
```

### TC-06.5: Topology gate on setup

Run setup on a Hub that already has DR artifacts without the force flag. Expected: assert fires "EXISTING DR TOPOLOGY DETECTED".

```bash
ansible-playbook playbooks/setup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-02-sa \
  -e is_primary_hub=false \
  -v
```

### TC-06.6: Missing KUBECONFIG context

Nonexistent source context. Expected: connectivity check fails with actionable error message.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=nonexistent-hub-sa_to_acmdr-hub-02-sa \
  -e acm_dr_failover_manager_dry_run=true \
  -v
```

---

## Phase 7: Cleanup and decommission

Decommission a Hub that was part of the DR topology. Removes MCH, OADP config, Observability, GitOps config, and automation RBAC. Preserves the GitOps/OADP operators and Azure backup data by default.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

### TC-07.1: Dry-run cleanup on Hub-02

```bash
ansible-playbook playbooks/cleanup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-02-sa \
  -e acm_dr_hub_cleanup_confirm=true \
  -e acm_dr_hub_cleanup_dry_run=true \
  -v
```

### TC-07.2: Production cleanup on Hub-02

```bash
ansible-playbook playbooks/cleanup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-02-sa \
  -e acm_dr_hub_cleanup_confirm=true \
  -v
```

### TC-07.4: Cross-hub storage dependency warning

**`purge_azure_storage=true`** attempts to remove the shared Azure Storage. **`known_peer_hubs`** triggers a cross-hub BSL check before purging.

```bash
ansible-playbook playbooks/cleanup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-02-sa \
  -e acm_dr_hub_cleanup_confirm=true \
  -e acm_dr_hub_cleanup_purge_azure_storage=true \
  -e 'acm_dr_hub_cleanup_known_peer_hubs=["acmdr-hub-01-sa"]' \
  -v
```

### TC-07.5: Cleanup confirmation gate

Without **`confirm=true`**. Expected: assert fires, lists what will be permanently removed.

```bash
ansible-playbook playbooks/cleanup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-02-sa \
  -v
```

---

## Phase 8: Multi-hub topology (3-hub)

1 active + 2 passive hub architecture. Tests passive sync Restore recycling when the active hub changes, ensuring all remaining passive hubs switch to restoring from the new leader's backups.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

### TC-08.2: Re-setup Hub-02 as passive

After Phase 7 cleanup.

```bash
ansible-playbook playbooks/setup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-02-sa \
  -e is_primary_hub=false \
  -v
```

### TC-08.3: Setup Hub-03 as passive

Fresh cluster, no previous DR artifacts.

```bash
ansible-playbook playbooks/setup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-hub-03-sa \
  -e is_primary_hub=false \
  -v
```

### TC-08.6: Failover Hub-01 to Hub-02 with additional passive hub

**`additional_passive_hubs`** tells Stage 06a to recycle Hub-03's passive sync Restore so it starts restoring from the new leader (Hub-02).

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-01-sa_to_acmdr-hub-02-sa \
  -e 'acm_dr_failover_manager_additional_passive_hubs=["acmdr-hub-03-sa"]' \
  -e skip_gates=true \
  -v
```

### TC-08.10: Failback Hub-02 to Hub-01 with additional passive hub

Same multi-hub pattern in reverse. Hub-03's Restore is recycled again.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-02-sa_to_acmdr-hub-01-sa \
  -e 'acm_dr_failover_manager_additional_passive_hubs=["acmdr-hub-03-sa"]' \
  -e skip_gates=true \
  -v
```

### TC-08.12: Skip passive recycling flag

**`skip_passive_recycling=true`** completely skips Stage 06a.

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e failover_direction=acmdr-hub-01-sa_to_acmdr-hub-02-sa \
  -e acm_dr_failover_manager_skip_passive_recycling=true \
  -e skip_gates=true \
  -v
```

---

## Phase 9: Spoke lifecycle

Full Spoke lifecycle (detach and re-onboard). Detach follows [KCS 5950901](https://access.redhat.com/solutions/5950901) to cleanly remove the klusterlet and agent namespaces before deleting the ManagedCluster object.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

### TC-09.1: Graceful Spoke detach (aro-classic-spoke-01)

**`action=detach`** + **`--tags spoke_detach`**. Both are required: the tag selects the task file, the action var passes the when condition.

```bash
ansible-playbook playbooks/manage-spoke.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e acm_dr_spoke_manager_action=detach \
  -e acm_dr_spoke_manager_cluster_name=aro-classic-spoke-01 \
  -e acm_dr_spoke_manager_spoke_k8s_context=aro-classic-spoke-01-sa \
  --tags spoke_detach \
  -v
```

### TC-09.3: Re-onboard same Spoke (aro-classic-spoke-01)

After detach, re-onboard the same Spoke.

```bash
ansible-playbook playbooks/manage-spoke.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e acm_dr_spoke_manager_action=prep \
  -e acm_dr_spoke_manager_cluster_name=aro-classic-spoke-01 \
  -e acm_dr_spoke_manager_spoke_k8s_context=aro-classic-spoke-01-sa \
  --tags spoke_prep \
  -v
```

### TC-09.4: Detach idempotency

Re-run on already-detached Spoke. Expected: no errors, all tasks skip or no-op cleanly.

```bash
ansible-playbook playbooks/manage-spoke.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e acm_dr_spoke_manager_action=detach \
  -e acm_dr_spoke_manager_cluster_name=aro-classic-spoke-01 \
  -e acm_dr_spoke_manager_spoke_k8s_context=aro-classic-spoke-01-sa \
  --tags spoke_detach \
  -v
```

---

## Phase 10: ArgoCD instance management

Provision and cleanup parametric ArgoCD instances. Instance configuration is passed via a vars file (**`-e @<file>`**) or inline YAML.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

### TC-10.1: Create parametric ArgoCD instance

Replace **`<INSTANCE_VARS_FILE>`** with the path to a YAML file containing the instance definition (namespace, repo secret, ApplicationSet generator, RBAC, ConsoleLink).

```bash
ansible-playbook playbooks/manage-argocd-instance.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e @<INSTANCE_VARS_FILE> \
  -v
```

### TC-10.3: Cleanup ArgoCD instance

```bash
ansible-playbook playbooks/cleanup-argocd-instance.yml \
  -e k8s_target_context=acmdr-hub-01-sa \
  -e acm_argocd_instance_cleanup_confirm=true \
  -e @<INSTANCE_VARS_FILE> \
  -v
```

---

## Phase 11: DR readiness check

> **Note:** Phase numbering in this file differs from the test matrix ([e2e-validation-matrix.md](e2e-validation-matrix.md)). The matrix assigns Phase 11 to scripts validation; this file assigns Phase 11 to DR readiness checks. Both are correct for their respective scope.

Read-only health assessment of the DR topology. Runs against both Hubs without making any changes. Checks five conditions: BackupSchedule health on the active Hub, BackupStorageLocation availability on both Hubs, RPO compliance (time since last successful backup), minimum active Spoke count, and passive sync Restore CR health on the passive Hub.

The check reports a pass/warn/fail for each condition and exits non-zero when any hard condition fails, making it suitable for CI gates, scheduled AAP jobs, and pre-failover validation.

Before running: confirm you sourced the dedicated kubeconfig.

```bash
source .local/cloud/azure/env-setup.sh
```

Key parameters:

| Parameter | Purpose | Default |
|-----------|---------|---------|
| **`-e k8s_source_context=<ctx>`** | Active (source) Hub context (`*-sa`) | Required |
| **`-e k8s_dest_context=<ctx>`** | Passive (destination) Hub context (`*-sa`) | Required |
| **`-e acm_dr_readiness_check_rpo_threshold_minutes=60`** | Minutes since last backup before RPO warning fires | **`60`** |
| **`-e acm_dr_readiness_check_min_spoke_count=1`** | Minimum expected Spoke count; fewer triggers a warning | **`1`** |

### TC-11.1: DR readiness check (both Hubs)

Full read-only assessment of both Hubs. Reports BackupSchedule state, BSL availability, RPO, Spoke count, and passive Restore health.

```bash
ansible-playbook playbooks/check-dr-readiness.yml \
  -e k8s_source_context=acmdr-hub-01-sa \
  -e k8s_dest_context=acmdr-hub-02-sa \
  -v
```

### TC-11.2: Readiness check - RPO threshold violation

Lower the RPO threshold below the age of the last backup to confirm the threshold guard fires.

```bash
ansible-playbook playbooks/check-dr-readiness.yml \
  -e k8s_source_context=acmdr-hub-01-sa \
  -e k8s_dest_context=acmdr-hub-02-sa \
  -e acm_dr_readiness_check_rpo_threshold_minutes=1 \
  -v
```

Expected: ⚠️ RPO warning appears in the readiness report. The check still completes (RPO is a warning, not a hard failure) but exits with a non-zero status when combined with other hard failures.

---

## Phase 12: WF-01 failure path (approval denial)

These test cases run through AAP, not `ansible-playbook` directly. They require:

- AAP gateway URL and API token in `.local/aap/aap_token.env` as `AAP_URL` and `AAP_TOKEN`
- WF-01 (WFT ID 18) already imported via CasC
- JT-10 (Check Approval Outcome, JT ID 26) deployed and attached to the WF-01 failure branch
- `ACM DR - AAP Automation Token` and `ACM DR - Notification Webhook` credentials attached to JT-10 at the WFT node level

For the full results and bug analysis, see [AAP integration validation](e2e-validation-aap.md#aap-27-gateway-api-gotchas).

### TC-12.1: WF-01 approval denial path

Launch WF-01, let the dry-run complete, deny the approval gate, and verify JT-10 classifies the event as "Approval Denied."

```bash
source .local/aap/aap_token.env

# 1. Launch WF-01
LAUNCH=$(curl -s -X POST \
  "${AAP_URL}/api/controller/v2/workflow_job_templates/18/launch/" \
  -H "Authorization: Bearer ${AAP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"extra_vars": {"acm_dr_failover_action": "failover"}}')
WF_JOB_ID=$(echo "${LAUNCH}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['id'])")
echo "WF job: ${WF_JOB_ID}"

# 2. Wait for the approval gate (poll; the dry-run takes ~2 min)
#    Approval appears under ?status=pending; do NOT use ?job=<wft_id> (invalid filter in AAP 2.7)
curl -s "${AAP_URL}/api/controller/v2/workflow_approvals/?status=pending&order_by=-id" \
  -H "Authorization: Bearer ${AAP_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d.get('results', []):
    print('approval id=%s name=%s status=%s' % (r['id'], r['name'], r['status']))
"

# 3. Deny the approval (replace <APPROVAL_ID> with the ID from step 2)
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST \
  "${AAP_URL}/api/controller/v2/workflow_approvals/<APPROVAL_ID>/deny/" \
  -H "Authorization: Bearer ${AAP_TOKEN}" \
  -H "Content-Type: application/json"
# Expected: HTTP 204
```

Expected: JT-10 runs on the failure branch, exits `rc=0`, and posts a webhook notification with `title: "Approval Denied"` and `timed_out: false`.

Hub Primary remains ACTIVE (BackupSchedule enabled). No production failover state is modified.

### TC-12.2: WF-01 approval timeout path

This path is equivalent to TC-12.1 but tests `timed_out=true`. Set the approval node timeout to 1 minute in the WFT definition (via CasC `timeout: 60`), launch WF-01, and let the gate expire without acting on it.

Expected: JT-10 runs, `_approval_timed_out=true`, notification `title: "Approval Timed Out"`. This path has not been run in the lab yet (timeout is 30 min by default). To avoid a 30-minute wait, reduce the WFT node timeout to 1 minute before the test run:

```bash
# Find the approval node's WFT node ID
curl -s "${AAP_URL}/api/controller/v2/workflow_job_templates/18/workflow_nodes/" \
  -H "Authorization: Bearer ${AAP_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for n in d.get('results', []):
    ujt = n.get('summary_fields',{}).get('unified_job_template',{})
    if ujt.get('unified_job_type') == 'workflow_approval':
        print('node_id=%s timeout=%s' % (n['id'], n.get('timeout', 'not set')))
"

# Patch the timeout to 60 seconds (restore after the test)
curl -s -X PATCH \
  "${AAP_URL}/api/controller/v2/workflow_job_template_nodes/<NODE_ID>/" \
  -H "Authorization: Bearer ${AAP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"timeout": 60}'
```
