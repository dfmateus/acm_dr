# E2E validation matrix: AWS ROSA HCP Hub tests

AWS-specific infrastructure provisioning, storage operations, OADP-on-STS validation, and cleanup tests for the ACM DR collection running on ROSA HCP Hub clusters. This file covers the cloud-provider layer (Terraform provisioning, S3 bucket storage, OADP manual install for STS) while the cloud-agnostic phases (failover, Spoke lifecycle, ArgoCD, safety gates) live in the [main E2E validation matrix](e2e-validation-matrix.md). For copy-paste commands, see the [E2E command reference](e2e-command-reference.md).

> **Scope**: 3 ROSA HCP Hub clusters in us-east-1, S3-based storage for OADP backups and Thanos observability, static IAM keys for OADP S3 credentials. Reuses existing Spoke fleet (cross-cloud: ARO Classic, ARO HCP, AKS, EKS).

<!-- Design spec: ROSA HCP Hub support (internal reference removed - content is in the test gates below). -->

## Table of contents

<!-- markdownlint-disable MD051 -->

- [AWS prerequisites](#aws-prerequisites)
- [Gate 1: Infrastructure provisioning (Day 0)](#gate-1-infrastructure-provisioning-day-0)
- [Gate 2: Onboarding and SA provisioning (Day 0)](#gate-2-onboarding-and-sa-provisioning-day-0)
- [Gate 3: Single Hub setup (Day 1)](#gate-3-single-hub-setup-day-1)
- [Gate 4: Passive Hubs (Day 1)](#gate-4-passive-hubs-day-1)
- [Gate 5: Spoke onboarding (Day 1-2)](#gate-5-spoke-onboarding-day-1-2)
- [Gate 6: Dry-run failover (Day 2)](#gate-6-dry-run-failover-day-2)
- [Gate 7: Live failover, failback, and cleanup (Day 2-3)](#gate-7-live-failover-failback-and-cleanup-day-2-3)
- [AAP validation (Layer 3)](#aap-validation-layer-3)
- [Results summary](#results-summary)

<!-- markdownlint-enable MD051 -->

## AWS prerequisites

These prerequisites are specific to AWS-based testing. For generic prerequisites (tooling, KUBECONFIG, collections), see the [main matrix prerequisites](e2e-validation-matrix.md#prerequisites).

### AWS account and tooling

- [ ] AWS account with sufficient quota for ROSA HCP clusters (each requires ~8 vCPUs in the target region, 3 clusters = 24 vCPUs)
- [ ] **`aws`** CLI authenticated (**`aws sts get-caller-identity`** to confirm identity)
- [ ] **`terraform`** >= 1.5.0 installed
- [ ] OCM token for **`TF_VAR_token`** (from [console.redhat.com/openshift/token](https://console.redhat.com/openshift/token))
- [ ] Static IAM access key for OADP S3 credentials (**`AWS_ACCESS_KEY_ID`**, **`AWS_SECRET_ACCESS_KEY`**)
- [ ] **`AWS_PROFILE`** and **`--region`** set explicitly in every command (never rely on implicit defaults)

### Terraform module

The [rh-mobb/terraform-rosa](https://github.com/rh-mobb/terraform-rosa) module (v1.0.0) is cloned locally at **`<local-terraform-clone-path>`**. It provisions VPC, subnets, IAM roles, OIDC, the ROSA HCP cluster, HTPasswd IDP, and handles cluster login automatically.

### Cluster parameters

| Variable | Hub-01 | Hub-02 | Hub-03 |
|----------|--------|--------|--------|
| **`cluster_name`** | **`acmdr-rosa-lab-hub-01`** | **`acmdr-rosa-lab-hub-02`** | **`acmdr-rosa-lab-hub-03`** |
| **`hosted_control_plane`** | **`true`** | **`true`** | **`true`** |
| **`compute_machine_type`** | **`m5.2xlarge`** | **`m5.2xlarge`** | **`m5.2xlarge`** |
| **`multi_az`** | **`false`** | **`false`** | **`false`** |
| **`replicas`** | **`2`** | **`2`** | **`2`** |
| **`region`** | **`us-east-1`** | **`us-east-1`** | **`us-east-1`** |
| **`vpc_cidr`** | **`10.10.0.0/16`** | **`10.11.0.0/16`** | **`10.12.0.0/16`** |
| **`private`** | **`false`** | **`false`** | **`false`** |

### Status symbols

| Symbol | Meaning |
|--------|---------|
| ✅ | PASS |
| ❌ | FAIL |
| ⚠️ | PARTIAL (passed with caveats) |
| 🔎 | SKIPPED (not applicable or deferred) |
| ⬜ | NOT RUN |

---

## Gate 1: Infrastructure provisioning (Day 0)

Terraform provisions 3 ROSA HCP clusters in parallel (separate state directories). Each cluster takes ~35-45 minutes.

| ID | Test case | Command / procedure | Expected result | Status | Date | Notes |
|----|-----------|---------------------|-----------------|--------|------|-------|
| TC-G1.1 | Provision Hub-01 | **`terraform init && terraform plan -out=main.plan && terraform apply main.plan`** | ROSA HCP cluster Ready, console accessible | ✅ | 2026-08-14 | Lab environment, AWS account <aws-account-id>, rh-mobb/terraform-rosa v1.0.0, us-east-1, m5.2xlarge x2 |
| TC-G1.2 | Provision Hub-02 | Same as TC-G1.1, different state dir | ROSA HCP cluster Ready | ✅ | 2026-08-14 | Same sandbox, VPC 10.11.0.0/16 |
| TC-G1.3 | Provision Hub-03 | Same as TC-G1.1, different state dir | ROSA HCP cluster Ready | ✅ | 2026-08-14 | Same sandbox, VPC 10.12.0.0/16 |
| TC-G1.4 | Validate nodes on all 3 | **`oc get nodes --context <hub>-sa`** | 2 Ready worker nodes per cluster | ✅ | 2026-08-14 | All 3 Hubs: 2 Ready workers, OCP 4.22.8 |

---

## Gate 2: Onboarding and SA provisioning (Day 0)

Register contexts and provision ServiceAccounts using [*`examples/scripts/cluster-onboarding/02_provision_automation_sa.sh`*](../../examples/scripts/cluster-onboarding/02_provision_automation_sa.sh).

| ID | Test case | Command / procedure | Expected result | Status | Date | Notes |
|----|-----------|---------------------|-----------------|--------|------|-------|
| TC-G2.1 | Login and register Hub-01 context | **`oc login <API_URL> -u admin -p '<password>' && oc config rename-context ...`** | Context **`acmdr-rosa-lab-hub-01`** in dedicated KUBECONFIG | ✅ | 2026-08-14 | SA contexts: acmdr-rosa-lab-hub-01-sa, hub-02-sa, hub-03-sa |
| TC-G2.2 | Provision SA on Hub-01 | **`./examples/scripts/cluster-onboarding/02_provision_automation_sa.sh`** | Context **`acmdr-rosa-lab-hub-01-sa`** functional, cluster-admin | ✅ | 2026-08-14 | **`ansible-dr-orchestrator`** SA + cluster-admin CRB on all 3 Hubs |
| TC-G2.3 | Repeat for Hub-02 and Hub-03 | Same as TC-G2.1/G2.2 | **`acmdr-rosa-lab-hub-02-sa`**, **`acmdr-rosa-lab-hub-03-sa`** functional | ✅ | 2026-08-14 | S3 buckets: acmdr-backup-<GUID> / acmdr-obs-<GUID> (us-east-1) |

---

## Gate 3: Single Hub setup (Day 1)

Run **`acm_dr_hub_setup`** on Hub-01 as PRIMARY with AWS provider. This gate validates the most critical assumption: OADP on ROSA HCP with static IAM keys and manual operator installation (tasks 5.1.1a-c).

```bash
ansible-playbook playbooks/setup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-rosa-lab-hub-01-sa \
  -e is_primary_hub=true \
  -e acm_dr_hub_setup_cloud_provider=aws \
  -e acm_dr_hub_setup_aws_s3_bucket_backup=acmdr-rosa-lab-oadp-backup \
  -e acm_dr_hub_setup_aws_s3_bucket_observability=acmdr-rosa-lab-thanos-obs
```

| ID | Test case | Expected result | Status | Date | Notes |
|----|-----------|-----------------|--------|------|-------|
| TC-G3.1 | S3 buckets created | Versioning enabled, public access blocked | ✅ | 2026-08-14 | acmdr-backup-<GUID> + acmdr-obs-<GUID>, us-east-1 |
| TC-G3.2 | MultiClusterHub Running | **`cluster-backup: true`** enabled | ✅ | 2026-08-14 | MCH 2.17 on ROSA HCP (OCP 4.22 requires channel **`release-2.17`**) |
| TC-G3.3 | OADP operator installed (STS manual path) | Tasks 5.1.1a-c ran, OperatorGroup + Subscription + CSV Succeeded | ✅ | 2026-08-14 | channel resolved dynamically via PackageManifest.status.defaultChannel (stable on 4.22) |
| TC-G3.4 | DPA reconciled | DataProtectionApplication conditions all True | ✅ | 2026-08-14 | Secret name **`cloud-credentials`** (OADP 1.6+ compat); DPA Jinja2 whitespace bug fixed |
| TC-G3.5 | BSL phase Available | BackupStorageLocation connected to S3 | ✅ | 2026-08-14 | BSL Available on S3 bucket acmdr-backup-<GUID> |
| TC-G3.6 | Thanos connected to S3 | MultiClusterObservability Ready, Thanos pods Running | ✅ | 2026-08-14 | MCO Ready; Thanos on acmdr-obs-<GUID> |
| TC-G3.7 | BackupSchedule created | First backup Completed | ✅ | 2026-08-14 | First **`acm-credentials-schedule`** Completed on Hub-01 |
| TC-G3.8 | GitOps/ArgoCD deployed | 2 ArgoCD instances healthy | ✅ | 2026-08-14 | Stage 04 GitOps same as ARO; no AWS-specific changes needed |
| TC-G3.9 | Idempotency | Re-run same command, no changes (all tasks ok/skipped) | ✅ | 2026-08-14 | Added **`acm_dr_hub_setup_allow_existing_dr=true`** for re-runs with existing MCH |

---

## Gate 4: Passive Hubs (Day 1)

```bash
ansible-playbook playbooks/setup-acm-dr-hub.yml \
  -e k8s_target_context=acmdr-rosa-lab-hub-02-sa \
  -e is_primary_hub=false \
  -e acm_dr_hub_setup_cloud_provider=aws \
  -e acm_dr_hub_setup_aws_s3_bucket_backup=acmdr-rosa-lab-oadp-backup \
  -e acm_dr_hub_setup_aws_s3_bucket_observability=acmdr-rosa-lab-thanos-obs
```

| ID | Test case | Expected result | Status | Date | Notes |
|----|-----------|-----------------|--------|------|-------|
| TC-G4.1 | Hub-02 passive setup | Passive sync Restore active with **`syncRestoreWithNewBackups: true`** | ✅ | 2026-08-14 | Hub-02 passive; sync Restore active from shared S3 bucket |
| TC-G4.2 | Hub-03 passive setup | Same as TC-G4.1 | ✅ | 2026-08-14 | Hub-03 passive; same S3 bucket |
| TC-G4.3 | BSL pointing to shared S3 | Same S3 bucket as Hub-01 | ✅ | 2026-08-14 | All 3 Hubs share acmdr-backup-<GUID> |
| TC-G4.4 | Velero pods Running | Velero server pod Running on Hub-02 and Hub-03 | ✅ | 2026-08-14 | Velero pods Running on Hub-02 and Hub-03 |

---

## Gate 5: Spoke onboarding (Day 1-2)

Onboard 2-3 Spokes to Hub-01 (start with AKS and EKS for cross-cloud coverage).

| ID | Test case | Expected result | Status | Date | Notes |
|----|-----------|-----------------|--------|------|-------|
| TC-G5.1 | Onboard AKS Spoke | ManagedCluster Available, klusterlet Running, ManagedServiceAccount TokenReported: True | ✅ | 2026-08-14 | Spokes first detached from ARO Hub (Gate 5a), then all 7 onboarded to ROSA Hub-01 (Gate 5b) |
| TC-G5.2 | Onboard EKS Spoke | Same as TC-G5.1 | ✅ | 2026-08-14 | eks-spoke-01-sa; same AWS account as ROSA Hub - no cross-account issues |
| TC-G5.3 | Onboard ARO Spoke (optional) | Same as TC-G5.1 | ✅ | 2026-08-14 | Full fleet: ARO Classic x2, ARO HCP, AKS, EKS, GKE, IKS - all 7 Available on ROSA Hub |

---

## Gate 6: Dry-run failover (Day 2)

```bash
ansible-playbook playbooks/orchestrate-dr-failover.yml \
  -e acm_dr_failover_manager_source_context=acmdr-rosa-lab-hub-01-sa \
  -e acm_dr_failover_manager_dest_context=acmdr-rosa-lab-hub-02-sa \
  -e acm_dr_failover_manager_dry_run=true
```

| ID | Test case | Expected result | Status | Date | Notes |
|----|-----------|-----------------|--------|------|-------|
| TC-G6.1 | All stages complete | All stages show **`🔎 [DRY-RUN]`** messages, no real mutations | ✅ | 2026-08-14 | Hub-01→Hub-02 dry-run, all 7 Spokes in fleet; all 9 stages ran with DRY-RUN notices |
| TC-G6.2 | Safety guards pass | Stage 00 reversed-direction guard, explicit backup resolution | ✅ | 2026-08-14 | clusterID-based backup resolution worked on S3 (acmdr-backup-<GUID>) |
| TC-G6.3 | No side effects | Hub-01 still ACTIVE with BackupSchedule, Hub-02 still PASSIVE | ✅ | 2026-08-14 | Hub-01 remained ACTIVE/PRIMARY after dry-run |

---

## Gate 7: Live failover, failback, and cleanup (Day 2-3)

| ID | Test case | Expected result | Status | Date | Notes |
|----|-----------|-----------------|--------|------|-------|
| TC-G7.1 | Failover Hub-01 → Hub-02 | Restore Finished, Spokes reconnect to Hub-02, BackupSchedule on Hub-02 | ✅ | 2026-08-14 | Gate 7a; klusterlet bootstrap fallback (tasks 1.2.5-1.2.9b) triggered for stale ImportSucceeded condition; 7/7 Spokes reconnected |
| TC-G7.2 | Failback Hub-02 → Hub-01 | Reverse failover succeeds, Spokes return to Hub-01 | ✅ | 2026-08-14 | Gate 7b; fully automated (bootstrap fallback already merged); 7/7 Spokes returned |
| TC-G7.3 | Cleanup Hub-03 | ACM removed, OADP removed, S3 buckets preserved | ✅ | 2026-08-14 | Gate 8; **`cloud_provider=aws`**, **`confirm=true`**; S3 buckets preserved |
| TC-G7.4 | Cleanup with S3 purge | S3 buckets deleted (re-run with **`purge_aws_storage=true`** on Hub-03) | ✅ | 2026-08-14 | Gate 13e via AAP (job 340, 41min - MCH teardown); ROSA Hub-01 decommissioned |

---

## AAP validation (Layer 3)

After local CLI testing passes (Gates 1-7), replicate the pipeline on the AAP instance running on **`aro-classic-spoke-01`**.

### Prerequisites

- [ ] EE has **`amazon.aws`** collection and **`boto3`**/**`botocore`** packages
- [ ] Code synced to AAP (4-step bare-repo sync procedure per [AAP setup guide](../aap/aap-setup.md))
- [ ] "ACM DR - Target Cluster" credentials created for each ROSA HCP Hub
- [ ] AAP built-in "Amazon Web Services" credential created with static IAM keys
- [ ] Updated surveys tested (cloud_provider, S3 bucket fields)

| ID | Test case | AAP Job Template | Status | Date | Notes |
|----|-----------|-----------------|--------|------|-------|
| TC-AAP.1 | Hub-01 setup from AAP | ACM DR - LAB - Hub Setup (**`cloud_provider=aws`**, **`is_primary_hub=true`**) | ✅ | 2026-08-14 | Job 324, 2min6s; boto3 gap fixed via in-cluster BuildConfig pip layer |
| TC-AAP.2 | Hub-02 passive from AAP | ACM DR - LAB - Hub Setup (**`cloud_provider=aws`**, **`is_primary_hub=false`**) | 🔎 | 2026-08-14 | Validated via CLI Gate 4; passive Hub-02/03 do not differ between CLI and AAP (same vars, same KUBECONFIG) |
| TC-AAP.3 | Spoke onboard from AAP | ACM DR - LAB - Spoke Onboarding | ✅ | 2026-08-14 | Job 326, 58s; ROSA Hub-01 as target |
| TC-AAP.4 | Dry-run failover from AAP | ACM DR - LAB - Hub Switchover (**`dry_run=true`**) | ✅ | 2026-08-14 | Job 330, 1min54s; ROSA Hub-01→Hub-02 |
| TC-AAP.5 | Live failover from AAP | ACM DR - LAB - Hub Switchover (**`dry_run=false`**) | ✅ | 2026-08-14 | Job 334, 2min22s; ROSA Hub-01→Hub-02; Hub-02 became leader |
| TC-AAP.6 | Cleanup from AAP | ACM DR - LAB - Hub Cleanup (**`cloud_provider=aws`**) | ✅ | 2026-08-14 | Job 340, 41min (MCH teardown dominant); ROSA Hub-01 decommissioned |

---

## Cross-cloud fleet management (Layer 4)

Tests that validate a ROSA HCP Hub managing Spokes from other cloud providers and distributions. These scenarios exercise the distribution-agnostic onboarding path and verify that the DR pipeline handles heterogeneous fleet membership correctly. Run after Layers 1-3 pass on the ROSA-only configuration.

### Prerequisites

- [ ] At least one non-ROSA Spoke available (ARO, AKS, EKS, or GKE)
- [ ] Spoke registered and SA provisioned via [*`02_provision_automation_sa.sh`*](../../examples/scripts/cluster-onboarding/02_provision_automation_sa.sh)
- [ ] Spoke fleet Secret updated on the ROSA Hub

| ID | Test case | Description | Expected result | Status | Date | Notes |
|----|-----------|-------------|-----------------|--------|------|-------|
| TC-AWS-37 | Mixed fleet: ROSA Hub + ARO Spokes | Onboard ARO Classic Spoke(s) into a ROSA HCP Hub. Run dry-run failover with the mixed fleet | Spoke onboarding succeeds (OCP vendor labels auto-detected). Fleet compatibility check in Stage 01 shows ARO Spokes as OCP-compatible. Sanitization (Stage 07) runs the same **`auto-import-secret`** path for ARO Spokes | ✅ | 2026-08-14 | ARO Classic x2 + ARO HCP onboarded to ROSA Hub-01; dry-run (Gate 6) and live failover (Gate 7) both ran with mixed fleet |
| TC-AWS-38 | Mixed fleet: ROSA Hub + AKS Spoke | Onboard AKS Spoke into ROSA HCP Hub with vendor/cloud extra-vars | Non-OCP Spoke listed as "outside matrix scope" in fleet compatibility. Sanitization handles the **`auto-import-secret`** injection without OCP-specific assumptions | ✅ | 2026-08-14 | aks-spoke-01-sa onboarded alongside OCP Spokes; fleet compatibility report showed AKS correctly as "outside matrix scope" |
| TC-AWS-39 | Mixed fleet: ROSA Hub + EKS Spoke | Onboard EKS Spoke into ROSA HCP Hub. Same cloud provider, different distribution | Validates that **`kubernetes.core.k8s`** works identically for EKS targets when kubeconfig context is an SA token. No cloud-provider-specific code path differences vs. ARO/AKS | ✅ | 2026-08-14 | eks-spoke-01-sa onboarded to ROSA Hub; same AWS account; no cross-account issues |
| TC-AWS-40 | OADP STS path validation | Verify that **`oadp_install_method=manual_sts`** produces a working DPA on ROSA HCP (STS short-lived tokens for S3 access) | DPA reconciles to **`Available`**, BSL shows **`Available`**. Backup/Restore cycle completes without credential errors | ✅ | 2026-08-14 | Tasks 5.1.1a-c; OADP manual install path for ROSA HCP; BSL Available on acmdr-backup-<GUID> |
| TC-AWS-41 | Failover between two ROSA Hubs | Full DR failover between ROSA Hub-A and ROSA Hub-B sharing the same S3 bucket | All 9 stages complete. Explicit backup resolution finds the correct clusterID. BackupSchedule paused on the source, created on the destination. Spokes reconnect to the new leader | ✅ | 2026-08-14 | Gates 7a + 7b + 7c; Hub-01→Hub-02 live failover and failback; Hub-01→Hub-03 failover (3-hub topology) |
| TC-AWS-42 | Backup age gate on S3 | Run dry-run failover and verify the backup age check (task 0.3.9a-d) works with S3-backed Velero Backups | Backup age line appears in the compliance report Executive Summary. Same Velero API, different storage backend (S3 vs. Azure Blob) | ✅ | 2026-08-14 | Backup age check ran in all ROSA dry-run and live runs; Velero API identical regardless of backend |
| TC-AWS-43 | Fleet Secret resolver with ROSA context | Verify **`acm_dr_kubeconfig_resolver`** discovers Spoke contexts from the fleet Secret on a ROSA Hub | Runtime kubeconfig at **`/tmp/acm_dr_runtime_kubeconfig.yml`** contains all Spoke contexts from the fleet Secret. SA tokens work for API calls to each Spoke | ✅ | 2026-08-14 | Resolver ran in every ROSA failover/failback; runtime kubeconfig built correctly for all 7 Spoke contexts |
| TC-AWS-44 | Compliance report on ROSA | Verify the compliance report renders correctly with ROSA Hub contexts (naming, version display, fleet compatibility) | Hub names display correctly. OCP version shows the ROSA HCP version. Fleet compatibility matrix evaluates OCP Spokes against the ROSA Hub's RHACM version | ✅ | 2026-08-14 | Postflight report (Stage 08) ran on ROSA Hub-01/02/03; Hub names and OCP 4.22.8 displayed correctly |

---

## Results summary

| Section | Total | ✅ Pass | 🔎 Skipped | ❌ Fail | ⬜ Not run | Notes |
|---------|-------|---------|------------|---------|------------|-------|
| Gate 1: Infrastructure | 4 | 4 | | | | Lab environment, 2026-08-14 |
| Gate 2: Onboarding | 3 | 3 | | | | All 3 Hub SA contexts functional |
| Gate 3: Single Hub setup | 9 | 9 | | | | Key OADP-on-STS validation |
| Gate 4: Passive Hubs | 4 | 4 | | | | Hub-02 + Hub-03 passive |
| Gate 5: Spoke onboarding | 3 | 3 | | | | All 7 Spokes, 5 distros, 4 clouds |
| Gate 6: Dry-run failover | 3 | 3 | | | | Hub-01→Hub-02, all 7 Spokes |
| Gate 7: Live failover/cleanup | 4 | 4 | | | | Failover + failback + Hub-03 failover + cleanup |
| AAP validation | 6 | 5 | 1 | | | TC-AAP.2 skipped (passive Hub validated via CLI Gate 4) |
| Cross-cloud fleet | 8 | 8 | | | | Mixed fleet + STS + resolver all confirmed |
| **TOTAL** | **44** | **43** | **1** | | | All ROSA HCP E2E complete - 2026-08-14 |
