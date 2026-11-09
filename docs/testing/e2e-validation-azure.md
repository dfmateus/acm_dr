# E2E validation matrix: Azure-specific tests

Azure-specific infrastructure provisioning, storage operations, and cleanup tests for the ACM DR collection. This file covers the cloud-provider layer (ARO cluster provisioning, Azure Blob Storage, Service Principal RBAC) while the cloud-agnostic phases (failover, Spoke lifecycle, ArgoCD, safety gates) live in the [main E2E validation matrix](e2e-validation-matrix.md). For copy-paste commands, see the [E2E command reference](e2e-command-reference.md).

> **Scope**: 3 ARO Classic Hub clusters on Azure (eastus), shared Azure Blob Storage Account for OADP backups and Thanos observability. Storage provisioned via **`azure.azcollection`** modules (no **`az`** CLI dependency after Phase 3 migration).

## Table of contents

<!-- markdownlint-disable MD051 -->

- [Azure prerequisites](#azure-prerequisites)
- [Phase 0: Azure infrastructure provisioning](#phase-0-azure-infrastructure-provisioning)
- [Phase 1: Azure Storage provisioning](#phase-1-azure-storage-provisioning)
- [Phase 7: Azure Storage cleanup](#phase-7-azure-storage-cleanup)
- [AAP validation (Azure cloud provider)](#aap-validation-azure-cloud-provider)
- [AAP Round 2 (Azure provider, full AAP-only cycle)](#aap-round-2-azure-provider-full-aap-only-cycle)
- [Results summary](#results-summary)

<!-- markdownlint-enable MD051 -->

## Azure prerequisites

These prerequisites are specific to Azure-based testing. For generic prerequisites (tooling, KUBECONFIG, collections), see the [main matrix prerequisites](e2e-validation-matrix.md#prerequisites).

### Azure subscription and tooling

- [ ] Azure subscription with sufficient quota for 3 ARO clusters (each requires ~36 vCPUs)
- [ ] **`az`** CLI authenticated (**`az login --use-device-code`** for headless)
- [ ] Service Principal with **`Storage Blob Data Contributor`** role on the target Resource Group

### ARO cluster provisioning and context registration

Each Hub cluster goes through 3 steps before the automation can use it:

**Step 1: Provision the ARO cluster** (Azure Portal or CLI):

```bash
# Example for Hub-01 (repeat for Hub-02 and Hub-03 adjusting names)
az group create -n acmdr-lab-hub-01-rg -l eastus
az aro create -g acmdr-lab-hub-01-rg -n acmdr-lab-hub-01 --domain hub-01 \
  --version 4.18.34 \
  --master-vm-size Standard_D8s_v3 --worker-vm-size Standard_D8s_v3 --worker-count 3 \
  --vnet acmdr-lab-hub-01-vnet --master-subnet master-subnet --worker-subnet worker-subnet
```

**Step 2: Login and register the context** in the dedicated KUBECONFIG:

```bash
# Get the kubeadmin credentials
az aro list-credentials -g acmdr-lab-hub-01-rg -n acmdr-lab-hub-01 -o json

# Login to the cluster (the API URL comes from az aro show)
oc login https://api.<hub-01-domain>.<region>.aroapp.io:6443 -u kubeadmin -p '<password>'

# Rename the auto-generated context to a friendly name
oc config rename-context "$(oc config current-context)" acmdr-lab-hub-01
# Output: Context "default/api-hub-01-eastus-aroapp-io:6443/kube:admin" renamed to "acmdr-lab-hub-01".
```

**Step 3: Provision the Zero-Trust automation ServiceAccount** using [*`examples/scripts/cluster-onboarding/02_provision_automation_sa.sh`*](../../examples/scripts/cluster-onboarding/02_provision_automation_sa.sh):

```bash
./examples/scripts/cluster-onboarding/02_provision_automation_sa.sh
# Select option 1 (Onboard all contexts)
# The script creates the ansible-dr-orchestrator SA, ClusterRoleBinding,
# and registers a permanent *-sa context for each cluster:
#   acmdr-lab-hub-01-sa, acmdr-lab-hub-02-sa, acmdr-lab-hub-03-sa
```

### Azure Resource Group for shared storage

The automation (Stage 01 of [*`acm_dr_hub_setup`*](../../roles/acm_dr_hub_setup)) creates the Azure Storage Account and Blob containers **inside** an existing Resource Group. It does **not** create the RG itself. Ensure the RG referenced by **`RESOURCEGROUP`** in **`.local/cloud/azure/env-setup.sh`** exists before running the lab setup:

```bash
az group create -n <resource-group> -l eastus
```

### Azure environment variables

**`.local/cloud/azure/env-setup.sh`** (copied from [*`examples/config/env-setup.sh.example`*](../../examples/config/env-setup.sh.example)) must export these Azure-specific variables:

| Variable | Purpose |
|----------|---------|
| **`SUBSCRIPTION`** | Azure subscription ID |
| **`TENANT`** | Azure AD / Entra ID tenant ID |
| **`CLIENT_ID`** | Service Principal client ID |
| **`PASSWORD`** | Service Principal client secret |
| **`RESOURCEGROUP`** | Azure RG for storage resources (must exist, see above) |
| **`GUID`** | Lab environment identifier (used in storage account naming: **`acmsa<GUID>`**) |

On AAP, the built-in "Microsoft Azure Resource Manager" credential type injects **`AZURE_SUBSCRIPTION_ID`**, **`AZURE_TENANT`**, **`AZURE_CLIENT_ID`**, and **`AZURE_SECRET`**. The role defaults read both naming conventions.

### Status symbols

| Symbol | Meaning |
|--------|---------|
| ✅ | PASS |
| ❌ | FAIL |
| ⚠️ | PARTIAL (passed with caveats) |
| 🔎 | SKIPPED (not applicable or deferred) |
| ⬜ | NOT RUN |

---

## Phase 0: Azure infrastructure provisioning

Manual steps outside the automation. Each cluster requires **`az aro create`**, context registration via [*`examples/scripts/cluster-onboarding/01_register_cluster.sh`*](../../examples/scripts/cluster-onboarding/01_register_cluster.sh), and SA provisioning via [*`examples/scripts/cluster-onboarding/02_provision_automation_sa.sh`*](../../examples/scripts/cluster-onboarding/02_provision_automation_sa.sh).

| ID | Test case | Command / procedure | Expected result | Status | Date | Notes |
|----|-----------|---------------------|-----------------|--------|------|-------|
| TC-00.1 | Provision ARO Hub-01 | **`az aro create -g acmdr-lab-hub-01-rg -n acmdr-lab-hub-01 --domain hub-01 --version 4.18.34 ...`** | ARO cluster Running, console accessible | ✅ | 2026-08-05 | OCP 4.18.34, 6 nodes, Standard_D8s_v3 |
| TC-00.2 | Provision ARO Hub-02 | **`az aro create -g acmdr-lab-hub-02-rg -n acmdr-lab-hub-02 --domain hub-02 --version 4.18.34 ...`** | ARO cluster Running, console accessible | ✅ | 2026-08-05 | OCP 4.18.34, 6 nodes, Standard_D8s_v3 |
| TC-00.3 | Provision ARO Hub-03 | **`az aro create -g acmdr-lab-hub-03-rg -n acmdr-lab-hub-03 --domain hub-03 --version 4.18.34 ...`** | ARO cluster Running, console accessible | ✅ | 2026-08-05 | OCP 4.18.34, 6 nodes, Standard_D8s_v3 |
| TC-00.4 | Register Hub-01 context | **`oc login ... && oc config rename-context ... acmdr-lab-hub-01`** | Context **`acmdr-lab-hub-01`** in dedicated KUBECONFIG | ✅ | 2026-08-05 | |
| TC-00.5 | Register Hub-02 context | **`oc login ... && oc config rename-context ... acmdr-lab-hub-02`** | Context **`acmdr-lab-hub-02`** in dedicated KUBECONFIG | ✅ | 2026-08-05 | |
| TC-00.6 | Register Hub-03 context | **`oc login ... && oc config rename-context ... acmdr-lab-hub-03`** | Context **`acmdr-lab-hub-03`** in dedicated KUBECONFIG | ✅ | 2026-08-05 | |
| TC-00.7 | Provision SA on all 3 Hubs | **`./examples/scripts/cluster-onboarding/02_provision_automation_sa.sh`** (option 1: onboard all) | Contexts `*-sa` functional for all 3 Hubs | ✅ | 2026-08-05 | ansible-dr-orchestrator SA with cluster-admin |
| TC-00.8 | Create shared storage RG | **`az group create -n <resource-group> -l eastus`** | RG exists for Azure Storage provisioning | ✅ | 2026-08-03 | Required by Stage 01 of acm_dr_hub_setup |

---

## Phase 1: Azure Storage provisioning

Tests specific to the Azure Blob Storage provisioning path ([*`acm_dr_hub_setup/tasks/azure/01_storage.yml`*](../../roles/acm_dr_hub_setup/tasks/azure/01_storage.yml)). The full pipeline tests (TC-01.1, TC-01.3 in the [main matrix](e2e-validation-matrix.md#phase-1-lab-setup-and-topology-detection)) exercise this path as part of the 7-stage setup. The tests below break out the Azure-specific validations individually.

| ID | Test case | Validated within | Expected result | Status | Date | Notes |
|----|-----------|------------------|-----------------|--------|------|-------|
| TC-01-AZ.1 | Azure credential validation via **`azure_rm_subscription_info`** | TC-01.1 (Step 1.1.1) | SP authenticates against Azure subscription, no 401/403 | ✅ | 2026-08-05 | Validated as part of Hub-01 full pipeline |
| TC-01-AZ.2 | Storage Account creation via **`azure_rm_storageaccount`** | TC-01.1 (Step 1.3.1) | Storage Account **`acmsa<GUID>`** created in RG **`<resource-group>`**, Standard_LRS, StorageV2, public access blocked | ✅ | 2026-08-05 | Idempotent: second Hub re-uses existing SA |
| TC-01-AZ.3 | Blob Container creation (backup + observability) via **`azure_rm_storageblob`** | TC-01.1 (Steps 1.3.2, 1.3.3) | Containers **`acm-backup`** and **`acm-observability`** created with **`auth_mode: login`** | ✅ | 2026-08-05 | Two containers in same Storage Account |
| TC-01-AZ.4 | Storage Blob Data Contributor role assignment via **`azure_rm_roleassignment`** | TC-01.1 (Step 1.4.1) | SP gets **`Storage Blob Data Contributor`** on the Storage Account scope. Requires **`azure_rm_adserviceprincipal_info`** to resolve client_id to object_id | ✅ | 2026-08-05 | Role assignment idempotent |
| TC-01-AZ.5 | Azure Storage reuse safety gate | TC-01.3 (Step 1.2.3) | Without **`azure_storage_allow_reuse=true`**, 🛡️ SAFETY LOCK fires when SA/containers exist. With flag, pipeline proceeds | ✅ | 2026-08-05 | Hub-02 setup required **`allow_reuse=true`** |
| TC-01-AZ.6 | Azure Storage provisioning summary report | TC-01.1 (Step 1.5) | Template **`reports/azure/01_storage_summary.j2`** renders correctly with SA name, RG, container names | ✅ | 2026-08-05 | Report shows all provisioned resources |

---

## Phase 7: Azure Storage cleanup

Tests specific to the Azure Blob Storage cleanup path ([*`acm_dr_hub_cleanup/tasks/azure/05_storage_cleanup.yml`*](../../roles/acm_dr_hub_cleanup/tasks/azure/05_storage_cleanup.yml)). The full cleanup pipeline is tested in the [main matrix Phase 7](e2e-validation-matrix.md#phase-7-cleanup-and-decommission); only the Azure storage purge is covered here.

| ID | Test case | Command / procedure | Expected result | Status | Date | Notes |
|----|-----------|---------------------|-----------------|--------|------|-------|
| TC-07-AZ.1 | Cross-hub storage dependency warning | **`ansible-playbook playbooks/cleanup-acm-dr-hub.yml -e k8s_target_context=acmdr-lab-hub-02-sa -e acm_dr_hub_cleanup_confirm=true -e acm_dr_hub_cleanup_purge_azure_storage=true -e 'acm_dr_hub_cleanup_known_peer_hubs=["acmdr-lab-hub-01-sa"]'`** | ⚠️ Warning: "Peer hub 'acmdr-lab-hub-01-sa' still has an Available BackupStorageLocation". Non-blocking | 🔎 | 2026-08-11 | Not exercised: peer Hubs were already clean (ACM removed) when the Azure Storage purge ran on Hub-01. The **`known_peer_hubs`** cross-check path remains untested |
| TC-07-AZ.2 | Azure Storage Account deletion | **`... -e acm_dr_hub_cleanup_purge_azure_storage=true -e acm_dr_hub_cleanup_azure_storage_account_name=acmsa<GUID> -e acm_dr_hub_cleanup_azure_resource_group=<resource-group>`** | Storage Account deleted via **`azure_rm_storageaccount`** (**`state: absent`**, **`force_delete_nonempty: true`**) | ✅ | 2026-08-11 | **(AAP)** JT 11 Job #272 (77s). Required **`force_delete_nonempty: true`** bug fix (the Storage Account contained OADP backup and Thanos containers). First two attempts failed: Job #268 (missing Azure Survey fields for resource group/storage account name) and Job #270 (**`force_delete_nonempty`** not set). Both bugs fixed and code re-synced to AAP EE before Job #272 |
| TC-07-AZ.3 | Azure Storage purge idempotency | Re-run TC-07-AZ.2 after purge | No errors, tasks skip or no-op (Storage Account already absent) | ⬜ | | Not explicitly re-run after Job #272. The **`azure_rm_storageaccount`** module handles absent accounts idempotently by design, but this specific path was not validated |
| TC-07-AZ.4 | Azure Storage cleanup inline status | Check TC-07-AZ.2 output (Stage 05 completion message) | Stage 05 inline **`debug`** message shows: "Storage Account 'acmsa<GUID>' and its Containers were permanently removed from Azure" | ✅ | 2026-08-11 | **(AAP)** Verified in Job #272 output. Stage 05 uses inline **`debug`** messages (not a Jinja2 template report) for the three paths: preserved (default), dry-run, and purged |

---

## AAP validation (Azure cloud provider)

Tests validating the **`common/`** + **`azure/`** subfolder reorganization works correctly when executed via AAP Job Templates. These tests confirm that **`import_tasks: common/...`** and **`include_tasks: azure/...`** paths resolve correctly inside the AAP Execution Environment.

**AAP instance**: [AAP on Azure](https://aap-aap.apps.<spoke-domain>.<region>.aroapp.io) running in namespace **`aap`** on cluster **`aro-classic-spoke-01-sa`**.

| ID | Test case | AAP Job | Extra vars | Expected result | Status | Date | Notes |
|----|-----------|---------|------------|-----------------|--------|------|-------|
| TC-AAP-AZ.1 | Hub Setup (azure provider, Hub-02 passive) | JT 8, Job #233 | **`k8s_target_context=acmdr-lab-hub-02-sa`**, **`is_primary_hub=false`**, **`acm_dr_hub_setup_azure_storage_allow_reuse=true`**, **`acm_dr_hub_setup_allow_existing_dr=true`**, **`acm_dr_hub_setup_azure_resource_group=<resource-group>`**, **`acm_dr_hub_setup_azure_storage_account_name=acmsa<GUID>`** | All 7 stages (00-06) complete. **`common/`** and **`azure/`** task paths resolve correctly | ✅ | 2026-08-10 | 132 ok, 0 failed. First time JT 8 ran the **`common/`** subfolder layout |
| TC-AAP-AZ.2 | Hub Cleanup dry-run (azure provider, Hub-02) | JT 11, Job #235 | **`k8s_target_context=acmdr-lab-hub-02-sa`**, **`acm_dr_hub_cleanup_dry_run=true`**, **`acm_dr_hub_cleanup_confirm=true`**, **`acm_dr_hub_cleanup_cloud_provider=azure`** | All 8 stages (00-07) complete in check_mode. **`common/`** and **`azure/`** paths resolve correctly | ✅ | 2026-08-10 | 73 ok, 0 failed. Validates cleanup role's **`common/`** layout |
| TC-AAP-AZ.3 | Hub Failover dry-run (regression, azure backend) | JT 9, Job #240 | **`acm_dr_failover_action=failover`**, **`acm_dr_failover_manager_dry_run=true`**, **`skip_gates=true`** | Preflight connects to both Hubs, pipeline runs in check_mode | ✅ | 2026-08-10 | Re-run after credential refresh. Hub-01→Hub-03 (Dest swapped because Hub-02 was clean). **`ok=139 changed=13 failed=0`** (284s). Per-cluster credential model validated end-to-end via kubeconfig_resolver. Previous Job #237 failed due to expired Hub-02 credential, not a code issue |
| TC-AAP-AZ.4 | Spoke detach via AAP (per-cluster credentials) | JT 10, Job #242 | **`acm_dr_spoke_manager_cluster_name=aro-classic-spoke-01`**, **`acm_dr_spoke_manager_action=detach`** | ManagedCluster removed, Klusterlet cleaned, agent namespaces purged | ✅ | 2026-08-10 | **`ok=37 changed=5 failed=0`** (87s). Per-cluster credential model (Target Hub + Spoke credentials) validated for spoke_detach flow |
| TC-AAP-AZ.5 | Spoke re-onboard via AAP (per-cluster credentials) | JT 10, Job #244 | **`acm_dr_spoke_manager_cluster_name=aro-classic-spoke-01`**, **`acm_dr_spoke_manager_action=prep`** | Spoke re-joins fleet, **`JOINED=True`**, **`AVAILABLE=True`** | ✅ | 2026-08-10 | **`ok=43 changed=12 failed=0`** (58s). Full spoke lifecycle (detach+prep) validated via AAP per-cluster credential model |
| TC-AAP-AZ.6 | Hub Setup passive re-provision (Hub-02) | JT 8, Job #246 | **`k8s_target_context=acmdr-lab-hub-02-sa`**, **`is_primary_hub=false`**, **`acm_dr_hub_setup_azure_storage_allow_reuse=true`**, **`acm_dr_hub_setup_azure_resource_group=<resource-group>`**, **`acm_dr_hub_setup_azure_storage_account_name=acmsa<GUID>`** | Hub-02 re-provisioned as PASSIVE after prior cleanup. All 7 stages complete | ✅ | 2026-08-10 | **`ok=142 changed=24 failed=0`** (820s). Re-provisioned as passive for dry-run failback (TC-03.14). Survey now includes **`k8s_target_context`** as text field |
| TC-AAP-AZ.7 | Spoke batch detach (7 Spokes) via AAP | JT 10, Jobs #248-#260 | **`acm_dr_spoke_manager_action=detach`**, one job per Spoke | All 7 Spokes detached cleanly: ManagedCluster removed, Klusterlet cleaned, agent namespaces purged | ✅ | 2026-08-10 | 7 sequential JT 10 launches with credential swaps (one Target Hub + one Spoke credential per job). All 7 returned **`changed>0 failed=0`**. Fleet reduced from 8 to 1 (local-cluster only) |
| TC-AAP-AZ.8 | Hub Cleanup passive (Hub-03) | JT 11, Job #262 | **`k8s_target_context=acmdr-lab-hub-03-sa`**, **`acm_dr_hub_cleanup_confirm=true`**, **`acm_dr_hub_cleanup_dry_run=false`** | Full cleanup pipeline on passive Hub-03: ACM, OADP, Observability, GitOps removed. Automation RBAC preserved | ✅ | 2026-08-11 | (752s). First of 3 sequential Hub cleanups (passives first, then active) |
| TC-AAP-AZ.9 | Hub Cleanup passive (Hub-02) | JT 11, Job #264 | **`k8s_target_context=acmdr-lab-hub-02-sa`**, **`acm_dr_hub_cleanup_confirm=true`**, **`acm_dr_hub_cleanup_dry_run=false`** | Full cleanup pipeline on passive Hub-02 | ✅ | 2026-08-11 | (948s). Second of 3 sequential cleanups |
| TC-AAP-AZ.10 | Hub Cleanup active with force + Azure purge (Hub-01) | JT 11, Job #272 | **`k8s_target_context=acmdr-lab-hub-01-sa`**, **`acm_dr_hub_cleanup_confirm=true`**, **`acm_dr_hub_cleanup_dry_run=false`**, **`acm_dr_hub_cleanup_force=true`**, **`acm_dr_hub_cleanup_purge_azure_storage=true`**, **`acm_dr_hub_cleanup_azure_resource_group=<resource-group>`**, **`acm_dr_hub_cleanup_azure_storage_account_name=acmsa<GUID>`** | Active Hub cleaned with force flag (bypasses "Hub looks ACTIVE" gate). Azure Storage Account **`acmsa<GUID>`** permanently deleted | ✅ | 2026-08-11 | (77s). Required two bug fixes before success: (1) Azure Survey fields missing for **`resource_group`**/**`storage_account_name`** (Jobs #268 failed), (2) **`force_delete_nonempty: true`** missing on **`azure_rm_storageaccount`** (Job #270 failed). Both fixed and code re-synced to AAP EE. See TC-07-AZ.2 |
| TC-AAP-AZ.11 | Survey sync (CasC alignment) | JTs 8, 9, 10 | Survey specs pushed via API **`POST /survey_spec/`** | All 5 JT Surveys match [*`examples/aap/controller_job_templates.yml`*](../../examples/aap/controller_job_templates.yml) definitions. JT 8: 5 fields, JT 9: 6 fields, JT 10: 5 fields, JT 11: 7 fields, JT 12: 3 fields | ✅ | 2026-08-11 | Corrections applied: JT 8 added **`k8s_target_context`**; JT 9 replaced **`failover_direction`** with **`acm_dr_failover_action`**, added **`allow_fenced_origin`**/**`target_acm_version`**/**`skip_version_gate`**; JT 10 added **`k8s_target_context`**/**`spoke_k8s_context`**, full cloud choices |

---

## AAP Round 2 (Azure provider, full AAP-only cycle)

A complete end-to-end validation ran exclusively through AAP Job Templates on 2026-08-11, re-exercising the Azure Storage provisioning path (Storage Account **`acmdr-storage-01`** in RG **`<resource-group>`**) and the per-cluster credential model across 13 AAP jobs. All Azure-specific operations (Storage Account creation, BSL provisioning, Blob Container setup) passed cleanly via JT 8 (Hub Setup).

Full results: [AAP integration validation](e2e-validation-aap.md).

| ID | Test case | AAP Job | Expected result | Status | Date | Notes |
|----|-----------|---------|-----------------|--------|------|-------|
| TC-AAP-AZ-R2.1 | Hub Setup PRIMARY (Azure Storage creation) | JT 8, Job 275 | Storage Account **`acmdr-storage-01`** created, Blob Containers provisioned, BSL Available | ✅ | 2026-08-11 | 813s. New SA name validates custom naming path. All Azure modules (azure_rm_storageaccount, azure_rm_storageblob, azure_rm_roleassignment) executed via AAP |
| TC-AAP-AZ-R2.2 | Hub Setup PASSIVE x2 (Azure Storage reuse) | JT 8, Jobs 291, 293 | **`azure_storage_allow_reuse=true`** accepted, existing SA/containers re-used without error | ✅ | 2026-08-11 | Hub-02 (780s) and Hub-03 (856s) both re-used **`acmdr-storage-01`** |
| TC-AAP-AZ-R2.3 | 7-Spoke onboarding (6 distributions, 4 clouds) | JT 12, Jobs 277-289 | All 7 Spokes JOINED+AVAILABLE. 3 OCP Spokes auto-detected cloud=Azure, 4 non-OCP required explicit cloud extra-var | ✅ | 2026-08-11 | See [AAP integration validation](e2e-validation-aap.md) for details |
| TC-AAP-AZ-R2.4 | 3-hub failover round-trip (Azure-backed OADP) | JT 9, Jobs 295-301 | OADP Restore from Azure Blob Storage worked across all 3 failover directions. Explicit backup resolution by ClusterID against shared Azure BSL | ✅ | 2026-08-11 | 4 failover operations (1 dry-run + 3 production) |
| TC-AAP-AZ-R2.5 | Rolling upgrade ACM 2.13 to 2.14 (3 Hubs) | JT 9, Jobs 303-307 + manual patches | 3 failover+upgrade cycles. Azure BSL remained Available across all ACM version transitions | ✅ | 2026-08-11 | See [AAP integration validation](e2e-validation-aap.md#operational-findings) |

---

## Results summary

| Section | Total | ✅ Pass | ❌ Fail | ⚠️ Partial | 🔎 Skip | ⬜ Not run | Notes |
|---------|-------|---------|---------|------------|---------|------------|-------|
| Phase 0: Azure infrastructure | 8 | 8 | | | | | All ARO clusters provisioned |
| Phase 1: Azure Storage | 6 | 6 | | | | | Validated within TC-01.1/TC-01.3 full pipeline |
| Phase 7: Azure Storage cleanup | 4 | 2 | | | 1 | 1 | Storage purge validated (Job #272). Cross-hub peer check untested (peers already clean). Idempotency not re-run |
| AAP validation (Azure, Round 1) | 11 | 11 | | | | | Full lab lifecycle via AAP: setup, failover, spoke detach/onboard, 3-hub cleanup, Survey sync |
| AAP Round 2 (Azure) | 5 | 5 | | | | | Full AAP-only cycle: storage creation, reuse, 7-Spoke onboarding, failover round-trip, rolling upgrade |
| **TOTAL** | **34** | **32** | | | **1** | **1** | |
