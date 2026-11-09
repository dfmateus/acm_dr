# 🐙 Ansible role: ArgoCD instance (acm_argocd_instance_setup)

A **fully generic and decoupled** role for provisioning named Red Hat OpenShift GitOps (ArgoCD) instances on a Red Hat Advanced Cluster Management for Kubernetes (RHACM) 2.10+ Hub.

Unlike Stage 04 of [acm_dr_hub_setup](../acm_dr_hub_setup), which assumes exactly 2 fixed instances (Governance + AppDemo), with names, namespaces, ApplicationSets, and application lists hardcoded in the Jinja templates, this role **does not assume any specific use case**. Each instance (name, namespace, Git repository, Application generator, RBAC, ConsoleLink) is entirely defined by the variables passed by the caller. You decide how many instances to create (0, 1, 5...) and what each one is used for.

This role is **additive**: it neither replaces nor depends on [*`acm_dr_hub_setup`*](../acm_dr_hub_setup); it coexists alongside it. It generically reuses all the GitOps multi-tenancy Field Findings discovered and fixed in [*`acm_dr_hub_setup`*](../acm_dr_hub_setup) (see its [*`README`*](../acm_dr_hub_setup/README.md) for the full history).

---

## 📂 Role file links

* [tasks/main.yml](tasks/main.yml): Dispatcher: executes each stage conditionally based on the provided variables.
* [defaults/main.yml](defaults/main.yml): Complete variable dictionary (documented inline, section by section).
* [templates/](templates/): All manifests are parameterized Jinja templates. No instance name, namespace, or app is hardcoded.

---

## 🧩 Usage model: instance list

The playbook [playbooks/manage-argocd-instance.yml](../../playbooks/manage-argocd-instance.yml) runs this role in a **`loop`** over an **`acm_argocd_instances`** list. Each loop item is an independent instance:

```yaml
acm_argocd_instances:
  - name: my-governance                # free-form name, chosen by the customer
    namespace: my-argocd-governance
    cluster_admin_rbac: true          # need to write outside its own namespace? enable here
    repo_url: "https://github.com/customer/repo.git"
    repo_username: "user"
    repo_pat: "{{ lookup('ansible.builtin.env', 'GITHUB_PAT') }}"
    wire_rhacm_integration: true      # required for the cluster_decision generator
    generator_type: cluster_decision
    placement_name: my-placement      # Placement defined in the repo's OWN content
    cluster_decision_path: "Policies"
    cluster_decision_destination_namespace: "my-policies"
    console_link_enabled: true
    console_link_text: "My Governance (custom)"

  - name: my-apps-demo
    namespace: my-argocd-apps
    cluster_admin_rbac: true
    repo_url: "https://github.com/customer/repo.git"
    generator_type: list
    managed_namespaces:                # pre-created via Ansible (avoids the "namespaced mode" lock)
      - { name: app-a, managed_by_label: true }
      - { name: app-b, managed_by_label: true }
    applications:
      - { name: app-a, path: "AppA", destination_namespace: app-a }
      - { name: app-b, path: "AppB", destination_namespace: app-b }
```

```bash
ansible-playbook playbooks/manage-argocd-instance.yml \
  -e k8s_target_context="acm-primary-hub-sa" \
  -e @my-instances.yml
```

---

## ⚙️ Key variables (defaults/main.yml)

| Variable | Required? | Description |
|---|---|---|
| **`acm_argocd_instance_setup_name`** | ✅ | ArgoCD instance name (and prefix for all derived resources: RBAC, ApplicationSet, Secret). |
| **`acm_argocd_instance_setup_namespace`** | ✅ | Instance namespace. |
| **`acm_argocd_instance_setup_manage_operator`** | No (default **`true`**) | Installs the OpenShift GitOps Operator if not already present (idempotent; cluster-wide, runs only once even with N instances). |
| **`acm_argocd_instance_setup_cluster_admin_rbac`** | No (default **`false`**) | Grants **`cluster-admin`** to this instance's **`application-controller`**. Required if the Applications' destination is a namespace **different** from the instance's namespace. |
| **`acm_argocd_instance_setup_repo_url`** / **`_repo_username`** / **`_repo_pat`** | conditional | If **`repo_url`** is provided, creates the Git credential Secret in the instance's namespace. |
| **`acm_argocd_instance_setup_managed_namespaces`** | No | List of namespaces to **pre-create via Ansible** (instead of ArgoCD's own **`CreateNamespace=true`**), avoiding the **`gitops-engine`** "namespaced mode" lock for cluster-scoped resources. Each item: **`{name, managed_by_label}`**. |
| **`acm_argocd_instance_setup_resource_exclusions`** | No | Excludes resource types (e.g., **`Namespace`**) from this instance's managed scope. Use when the customer's repository content declares that resource but the instance will never actually be able to manage it. |
| **`acm_argocd_instance_setup_generator_type`** | No (default **`none`**) | **`none`** (instance only, no ApplicationSet) / **`list`** (static app list) / **`cluster_decision`** (fan-out via RHACM Placement). |
| **`acm_argocd_instance_setup_applications`** | conditional (**`list`**) | List **`{name, path, destination_namespace, destination_server}`**. |
| **`acm_argocd_instance_setup_placement_name`** / **`_cluster_decision_path`** / **`_cluster_decision_destination_namespace`** | conditional (**`cluster_decision`**) | The Placement referenced here is content from the **customer's own repository**. This role does not create the business Policy/Placement, only the GitOps infrastructure that consumes it. |
| **`acm_argocd_instance_setup_wire_rhacm_integration`** | No (default **`false`**) | Creates **`GitOpsCluster`** + **`Placement`** (boilerplate, always points to **`local-cluster`**) + **`ManagedClusterSetBinding`**. Required once per instance using the **`cluster_decision`** generator. |
| **`acm_argocd_instance_setup_console_link_enabled`** / **`_console_link_text`** / **`_console_link_section`** | conditional | Publishes a shortcut in the OpenShift Console application menu. |

> ⚠️ **Note about the **`cluster_decision`** generator**: the template uses **`CreateNamespace=true`** on the **`destination_namespace`** (same pattern already validated in the Governance repository of **`acm_dr_hub_setup`**). If your customer's repository content declares a **`Namespace`** as a managed resource (same pitfall as the AppDemo Field Finding), pre-create that namespace via **`acm_argocd_instance_setup_managed_namespaces`** and exclude **`kind: Namespace`** via **`acm_argocd_instance_setup_resource_exclusions`**.

---

## 🚫 What this role does not do (by design)

* **Does not create RHACM Policies.** Governance is entirely GitOps-managed; the content (Policy, Placement, business PlacementBinding) lives in the customer's Git repository, versioned and auditable. An Ansible role that applied **`Policy`** CRs directly would compete with ArgoCD itself for resource ownership and bypass the history/PR-review that makes Policy-as-Code useful.
* **Does not decide how many or which Policies exist.** That is content from the repository referenced by **`repo_url`**/**`cluster_decision_path`**.

---

## ✅ Expected outcome

A successful run produces the following on the target Hub cluster (one set per instance in the list):

- ArgoCD CR in the instance namespace, **`phase: Available`**.
- **`GitOpsCluster`** and **`ManagedClusterSetBinding`** in the instance namespace (when **`wire_rhacm_integration: true`**).
- Git repository Secret in the instance namespace, labeled for ArgoCD credential discovery (when **`repo_url`** is provided).
- **`ApplicationSet`** CR using the configured generator (**`list`** or **`cluster_decision`**), with ArgoCD Applications in **`Synced`**/**`Healthy`** state (when generator_type is not **`none`**).
- **`ClusterRoleBinding`** granting **`cluster-admin`** to the instance's application controller SA (when **`cluster_admin_rbac: true`**).
- **`ConsoleLink`** in the OCP Console application menu (when **`console_link_enabled: true`**).
- Pre-created namespaces for managed workloads (when **`managed_namespaces`** list is provided).

---

## 🔄 Rollback

To remove an instance provisioned by this role, use [*`roles/acm_argocd_instance_cleanup`*](../acm_argocd_instance_cleanup). The cleanup role must be given the same **`name`**, **`namespace`**, and **`managed_namespaces`** list used during creation. Running the cleanup role without first collecting these values from the creation vars may miss managed namespaces.

The removal order in **`acm_argocd_instance_cleanup`** is strict: Applications before the ArgoCD instance. Reversing this order leaves the **`resources-finalizer.argocd.argoproj.io`** finalizer unprocessed and the namespace stuck in **`Terminating`**. The cleanup role handles this order automatically.

---

## 🧹 Removing an instance

See [*`roles/acm_argocd_instance_cleanup`*](../acm_argocd_instance_cleanup), the inverse operation of this role, with the correct removal order (Applications before the instance) to avoid orphaned finalizers.

---

## 📚 References

* [roles/acm_dr_hub_setup](../acm_dr_hub_setup): origin of the Field Findings reused here (GitOps multi-tenancy, cluster-scoped RBAC, gitops-engine namespaced mode).
* [Red Hat OpenShift GitOps - ArgoCD Custom Resource](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops)
* [Red Hat ACM - GitOpsCluster and ApplicationSet with PlacementDecision](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes)

---

Created and maintained by [Diego Felipe Mateus](https://github.com/dfmateus). See [CONTRIBUTORS.md](../../CONTRIBUTORS.md) for the list of contributors.
