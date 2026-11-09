# 🧹 Ansible role: Red Hat ACM DR lab cleanup (acm_dr_hub_cleanup)

This role is the **inverse operation** of [acm_dr_hub_setup](../acm_dr_hub_setup): it decommissions a cluster that was previously designated as a **Disaster Recovery (DR) node** for Red Hat Advanced Cluster Management for Kubernetes (RHACM) 2.10+, returning it to general-purpose use.

It does **not blindly uninstall everything**. The design principle is: remove only what is **specific to the DR node role**. The rest (generic operators that may serve other purposes in the cluster, and the actual backup data in Azure) is preserved by default.

---

## 🎯 Scope: what is removed and what stays (and why)

| Component | Default Action | Rationale |
|---|---|---|
| **Red Hat ACM** (MultiClusterHub CR **+** operator Subscription/CSV/OperatorGroup) | 🗑️ **Completely removed** | Unlike OADP and GitOps, ACM **is** the very reason the cluster exists as a DR node. It makes no sense to "be a DR node without ACM", so it is the only operator fully uninstalled. |
| **MultiClusterObservability** (Thanos) + namespace | 🗑️ **Completely removed** | It is a Custom Resource provided by the ACM operator itself (not a separate operator). Once ACM is removed, nothing remains to "operate" this CR. |
| **ArgoCD instances** for Governance (**`openshift-gitops-acm`**) and AppDemo (**`openshift-gitops-appdemo`**), ApplicationSets, RBAC, ConsoleLinks, console plugin | 🗑️ **Removed** | These instances and their namespaces were created specifically for RHACM governance/demonstration via GitOps. It makes no sense to keep them once the cluster stops being a DR node. |
| **Default ArgoCD instance from the operator** (**`openshift-gitops`**, namespace **`openshift-gitops`**) | 🟢 **Preserved** | It is created automatically by the GitOps operator itself during installation. It was never customized by this automation, so it is not removed. |
| **Red Hat OpenShift GitOps operator** (operator Subscription/CSV/namespace) | 🟢 **Preserved** | It is a generic CD tool. It may be serving other Applications/teams in the cluster that have nothing to do with DR. Removing it just because **`acm_dr_hub_setup`** installed it would be too destructive for the benefit. |
| **BackupSchedule** and **DataProtectionApplication** (OADP CRs) | 🗑️ **Removed** | These are the RHACM-specific backup configuration for this Hub. |
| **Red Hat OADP operator** (operator Subscription/CSV/OperatorGroup/namespace) | 🟡 **Preserved by design, but may be cascade-removed by ACM** | Same rationale as GitOps: OADP is a generic backup tool, reusable for any cluster workload. This role never removes it directly, but see the **⚠️ Real Finding** below: in environments where OADP was installed within the namespace that ACM's **`cluster-backup`** component also manages (the default for **`acm_dr_hub_setup`**), Stage 04 may cascade-remove it. |
| **ACM CustomResourceDefinitions** (cluster-scoped) | 🟢 **Preserved** | Removing them has high blast radius (affects the entire cluster) for low benefit. A future **`acm_dr_hub_setup`** can reuse them normally. See the note at the end of this section for manual removal, if truly desired. |
| **Storage Account + Containers in Azure** (Velero Backups and Thanos history) | 🟢 **Preserved by default** (**`acm_dr_hub_cleanup_purge_azure_storage=false`**) | The primary ACM Hub likely still depends on the **same shared storage**. Deleting this data by mistake would break DR for the entire fleet. Enable **`acm_dr_hub_cleanup_purge_azure_storage=true`** only if you are certain that no other Hub still depends on this data. **This action is irreversible.** |
| **Zero-Trust automation identity** (namespace **`ansible-automation`**, ServiceAccount **`ansible-dr-orchestrator`**, RBAC) | 🟢 **Preserved by default** (**`acm_dr_hub_cleanup_remove_automation_identity=false`**) | Removing the SA cuts the only non-interactive access to the cluster. Reconnecting afterward requires kubeadmin or another privileged user to re-provision the SA via [*`02_provision_automation_sa.sh`*](../../examples/scripts/cluster-onboarding/02_provision_automation_sa.sh). Enable with **`-e acm_dr_hub_cleanup_remove_automation_identity=true`** only when you intentionally want to revoke all automation access (full decommissioning, not just DR role removal). |

> 🔧 **Optional manual removal of ACM CRDs** (outside the scope of this role, as it is a command with higher blast radius): **`oc get crd -o name | grep -E 'open-cluster-management|hive.openshift.io|multicluster' | xargs oc delete`**. Only run this if you are absolutely certain that no other operator/CR in the cluster depends on these definitions.

---

## 🔬 Real finding: ACM's **`cluster-backup`** component also "owns" the OADP namespace

When testing this role end-to-end against a real Hub (**`acm-dr-hub-sa`**), including a complete cycle of cleanup, validation, reprovisioning via **`acm_dr_hub_setup`**, validation, and cleanup again, we discovered that the initial assumption "the OADP operator installed by **`acm_dr_hub_setup`** is independent and always survives ACM removal" **is not always true**.

### What we discovered
1. We ran the real cleanup (**`acm_dr_hub_cleanup_dry_run=false`**) against **`acm-dr-hub-sa`**. Stage 04 removed the **`MultiClusterHub`** normally, without errors.
2. When validating the final state, the namespace **`open-cluster-management-backup`** (where **`acm_dr_hub_setup`** installs the OADP operator, the **`DataProtectionApplication`**, and the **`BackupSchedule`**) **had also completely disappeared**, including the OADP operator's Subscription/CSV that lived there.
3. No task in this role touches that namespace directly (Stage 02 only removes **`BackupSchedule`**/**`DPA`**/**`Secret`**, never the namespace/operator). We confirmed this by reading the real execution log: there is no deletion call against **`open-cluster-management-backup`** anywhere in the playbook.
4. The root cause: the **`MultiClusterHub`** from **`acm_dr_hub_setup`** enables **`spec.overrides.components: [{name: cluster-backup, enabled: true}]`**. This component of ACM itself **manages its own copy** of the OADP operator (namespace, **`OperatorGroup`**, and its own **`Subscription`**, historically named **`redhat-oadp-operator-subscription`**) within the **same namespace** that **`acm_dr_hub_setup`** uses for its manual installation (**`open-cluster-management-backup`**). We confirmed this by inspecting the **`OperatorGroup`** in that namespace: its labels show **`installer.name: multiclusterhub`**, meaning it belongs to the MCH installer, not our automation.
5. When the **`MultiClusterHub`** is removed, the **`cluster-backup`** component itself tears down everything it considers its own, including the entire namespace, taking along anything that is inside, even if it was created manually by another automation.

### Why this matters
- This role remains **correct in intent**: it never decides to remove the OADP operator. What we discovered is a cascade from **another** controller (ACM itself), outside our control.
- This means that, in the reference topology used by this project (**`acm_dr_hub_setup`** installing OADP within the same namespace that ACM's **`cluster-backup`** manages), **the survival of the OADP operator after cleanup is not guaranteed**; it may vary depending on the Hub and the ACM reconciliation history.
- We validated, via **`oc get csv -A | grep -i oadp`**, that a second, completely independent instance of the OADP operator also exists in the **`openshift-adp`** namespace, confirming that the "OADP operator" as technology survives; only the instance placed within the namespace that ACM adopts as its own does not have guaranteed survival.

### What this implies for **`acm_dr_hub_setup`**

This same finding revealed, during test reprovisioning, a **pre-existing and more serious** problem in **`acm_dr_hub_setup`** itself: its manual OADP Subscription competed for the same **`OperatorGroup`** managed by **`cluster-backup`**, locking OLM into **`ConstraintsNotSatisfiable`** on a clean reinstallation. This finding (**already fixed and revalidated with a complete real failover/failback cycle**) is documented in detail in the [acm_dr_hub_setup](../acm_dr_hub_setup#-real-world-finding-olm-resolution-conflict-between-acm_dr_hub_setup-and-the-acm-cluster-backup-component) README.

---

## 🔬 Real finding: orphaned ConsoleLinks and RBAC due to divergent naming convention

After validating the complete cycle (cleanup → setup → cleanup), we manually inspected the real Hubs and found objects that survived **two real executions** of the cleanup with no errors reported:

- **`ConsoleLink`**s **`gitops-acm-acm-dr-hub`** and **`gitops-appdemo-acm-dr-hub`**, pointing to routes that no longer existed.
- A **`ClusterRoleBinding`** **`argo-admin-acm-ocp-acm-dr-hub`**.

### Root cause

The **`acm_dr_hub_setup`** names these objects including the **`k8s_target_context`** used **at the time of setup** (e.g., **`gitops-acm-acm-dr-hub`**, from an old execution that used the context **`acm-dr-hub`** without the **`-sa`** suffix). The first version of this role removed these objects by **exact name**, built with the **`k8s_target_context`** used **now, during cleanup** (**`acm-dr-hub-sa`**). Since the two strings did not match, the task found "nothing to remove" and reported success, but the objects remained orphaned forever, without the operator ever knowing.

### Correction applied
We replaced identification by name with identification by **actual object content**:
- **`ConsoleLink`**s are all discovered at once and filtered by **`spec.href`** (the destination route contains **`openshift-gitops-acm-server`** or **`openshift-gitops-appdemo-server`**, which are fixed names, independent of context).
- The **`ClusterRoleBinding`** is discovered by the actual **`subject`** (the ServiceAccount **`openshift-gitops-acm-argocd-application-controller`**), not by the binding's own name.

This covers any context convention used historically in setup, not just the current one. We validated the correction with dry-run and real execution against **`acm-dr-hub-sa`**: the two orphaned **`ConsoleLink`**s and the **`ClusterRoleBinding`** were correctly discovered and removed, leaving only the **`Cluster Argo CD`** ConsoleLink (the operator default, untouched by design).

> 💡 This finding is a good general reminder: whenever automation names resources using an input variable (such as **`k8s_target_context`**), the **inverse** automation (cleanup) should not trust that the same variable will have the same value. It is safer to identify objects by what they *actually are* (destination, subject, labels) than by the name that a past execution chose for them.

---

## 🛡️ Safety gates (Stage 00)

Since this role performs **destructive and, in part, irreversible** actions, Stage 00 applies three safety locks before any removal:

1. **Mandatory explicit confirmation** (**`acm_dr_hub_cleanup_confirm=true`**): without this flag, the role refuses to proceed, even in dry-run.
2. **Protection against accidentally decommissioning the ACTIVE Hub**: if the RHACM **`BackupSchedule`** exists and is **not** paused in the target context, this is a strong indication that the cluster is the primary production Hub. The role fails, unless you consciously confirm with **`acm_dr_hub_cleanup_force=true`**.
3. **Prior reconnaissance of the cluster's real state**: discovers what actually exists (MCH installed? BackupSchedule paused?) before acting, so that the final report and subsequent decisions reflect reality, not assumptions.

---

## 📋 Execution stages architecture

* **Stage 00 - Preflight & Safety Validation**: safety gates (explicit confirmation, active Hub protection) and current state reconnaissance.
* **Stage 01 - GitOps Cleanup**: removes ConsoleLinks, console plugin, ApplicationSets, RHACM integration (**`GitOpsCluster`**/**`Placement`**/**`ManagedClusterSetBinding`**), RBAC, and the ArgoCD instances (governance + appdemo) and their namespaces. **The GitOps operator is preserved.**
* **Stage 02 - OADP Cleanup**: removes **`BackupSchedule`**, **`DataProtectionApplication`**, and the Velero Azure credentials Secret. **The OADP operator and its namespace are preserved.**
* **Stage 03 - Observability Cleanup**: removes **`MultiClusterObservability`**, orphaned PVCs, and the Observability namespace.
* **Stage 04 - MCH/ACM Cleanup**: removes the **`MultiClusterHub`** (waits for complete teardown, 10-20 minutes) and fully uninstalls the ACM operator (Subscription/CSV/OperatorGroup/namespace).
* **Stage 05 - Azure Storage Cleanup**: **optional and disabled by default**. Only deletes the Storage Account/Containers in Azure if **`acm_dr_hub_cleanup_purge_azure_storage=true`** is explicitly provided.
* **Stage 06 - Automation RBAC Cleanup**: removes the Zero-Trust automation identity (runs last on purpose, to preserve administrative access throughout the rest of the cleanup).
* **Stage 07 - Final Report**: consolidated report of what was removed, what was preserved, and the final state in Azure.

> 📂 **Report centralization**: all textual content for banners and panels resides in [templates/reports/](templates/reports/). No task has inline report formatting. [stage_banner.j2](templates/reports/stage_banner.j2) is the generic template reused by all stage headers; [07_final_report.j2](templates/reports/07_final_report.j2) is the final consolidated report.

---

## ⚙️ Configuration variables (defaults/main.yml)

### Safety gates
* **acm_dr_hub_cleanup_confirm** (Default: **`false`**): must be **`true`** for the role to proceed beyond Stage 00.
* **acm_dr_hub_cleanup_force** (Default: **`false`**): overrides the "Hub appears to be active" lock.
* **acm_dr_hub_cleanup_dry_run** (Default: **`false`**): simulates all removal via Kubernetes-native **`check_mode`**/**`diff`** (**`dryRun=All`**), without applying any real changes.

### Cleanup scope
* **acm_dr_hub_cleanup_remove_automation_identity** (Default: **`false`**): when **`true`**, removes the Zero-Trust automation identity (namespace, SA, CRB). **Preserved by default** because removing the SA cuts the only non-interactive access to the cluster; reconnecting requires kubeadmin to re-provision the SA.
* **acm_dr_hub_cleanup_purge_azure_storage** (Default: **`false`**): when **`true`**, permanently deletes the Storage Account and Containers in Azure (**`az storage account delete --yes`**). **Irreversible action.**

### Resource names and namespaces
The variables **`acm_dr_hub_cleanup_mch_*`**, **`acm_dr_hub_cleanup_oadp_*`**, **`acm_dr_hub_cleanup_gitops_*`**, **`acm_dr_hub_cleanup_observability_*`**, and **`acm_dr_hub_cleanup_automation_*`** follow exactly the same default names/namespaces used by [acm_dr_hub_setup](../acm_dr_hub_setup). If your environment customized any of these names during setup, provide the same values here via **`-e`** so the cleanup finds the correct resources.

### Azure credentials (only required with **`acm_dr_hub_cleanup_purge_azure_storage=true`**)
**`acm_dr_hub_cleanup_azure_subscription_id`**, **`acm_dr_hub_cleanup_azure_tenant_id`**, **`acm_dr_hub_cleanup_azure_client_id`**, **`acm_dr_hub_cleanup_azure_client_secret`**, **`acm_dr_hub_cleanup_azure_resource_group`**, **`acm_dr_hub_cleanup_azure_storage_account_name`**. Read from the same environment variables (**`SUBSCRIPTION`**, **`TENANT`**, **`CLIENT_ID`**, **`PASSWORD`**, **`RESOURCEGROUP`**, **`GUID`**) used by **`acm_dr_hub_setup`**.

---

## 🚀 How to run

### 1. Recommended: simulate before applying for real (dry-run)

```bash
ansible-playbook playbooks/cleanup-acm-dr-hub.yml \
  -e k8s_target_context="acm-dr-hub" \
  -e acm_dr_hub_cleanup_confirm=true \
  -e acm_dr_hub_cleanup_dry_run=true
```

### 2. Decommission a secondary/passive DR node

```bash
ansible-playbook playbooks/cleanup-acm-dr-hub.yml \
  -e k8s_target_context="acm-dr-hub" \
  -e acm_dr_hub_cleanup_confirm=true
```

### 3. Full cleanup, including Storage Account/Containers in Azure (irreversible)

```bash
ansible-playbook playbooks/cleanup-acm-dr-hub.yml \
  -e k8s_target_context="acm-dr-hub" \
  -e acm_dr_hub_cleanup_confirm=true \
  -e acm_dr_hub_cleanup_purge_azure_storage=true
```

### 4. Partial execution via tags (e.g. remove only Governance/GitOps)

```bash
ansible-playbook playbooks/cleanup-acm-dr-hub.yml \
  -e k8s_target_context="acm-dr-hub" \
  -e acm_dr_hub_cleanup_confirm=true \
  --tags "gitops_cleanup"
```

Available tags per stage: **`preflight`**, **`gitops_cleanup`**, **`oadp_cleanup`**, **`observability_cleanup`**, **`mch_cleanup`**, **`azure_storage_cleanup`**, **`automation_cleanup`**.

---

## 🔎 Dry-run note

All mutable Kubernetes tasks use native **`check_mode`**/**`diff`** (**`dryRun=All`** validation at the API Server), the same mechanism already validated in the [acm_dr_failover_manager](../acm_dr_failover_manager) role. Azure CLI calls (Stage 05) do not natively support **`check_mode`**. In dry-run, they are skipped and replaced with a **`🔎 [DRY-RUN]`** message explaining exactly what would be removed.

---

## 📚 Official references
* [Red Hat ACM - Uninstalling](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes)
* [Red Hat OADP Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/backup_and_restore/oadp-application-backup-and-restore)
* [Red Hat OpenShift GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops)

---

Created and maintained by [Diego Felipe Mateus](https://github.com/dfmateus). See [CONTRIBUTORS.md](../../CONTRIBUTORS.md) for the list of contributors.
