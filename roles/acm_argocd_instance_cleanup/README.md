# 🧹 Ansible role: ArgoCD instance cleanup (acm_argocd_instance_cleanup)

**Inverse** of [acm_argocd_instance_setup](../acm_argocd_instance_setup): fully removes a named Red Hat OpenShift GitOps (ArgoCD) instance, without affecting the Operator (shared by other instances) or any other existing instance on the cluster.

---

## 📂 Role file links

* [tasks/main.yml](tasks/main.yml): Dispatcher: executes each stage in the correct order (see real-world finding below).
* [defaults/main.yml](defaults/main.yml): Variable dictionary.

---

## 🔬 Real-world finding: removal order and the ArgoCD finalizer

✅ **Fixed and validated in this version.** Discovered while testing manual removal of a real test instance.

When removing an ArgoCD instance's entire namespace at once (CR + Applications + the **`argocd-application-controller`** itself), the **`application-controller`** is terminated **before** it can process the **`resources-finalizer.argocd.argoproj.io`** finalizer on its own **`Application`**s. The namespace becomes stuck in **`Terminating`** indefinitely, requiring manual finalizer removal.

### Applied fix

The removal order is strictly:
1. **Applications/ApplicationSet first** (Stage 01): with the **`application-controller`** still running, it processes the finalizer correctly and performs a clean prune of the resources it managed.
2. **Managed namespaces, ConsoleLink, cluster-scoped RBAC** (Stages 02-04).
3. **The instance itself last** (Stage 05): ArgoCD CR + namespace, with a defense-in-depth self-healing step that removes the finalizer from any remaining **`Application`** in case the namespace still gets stuck.

### Fix validation

Tested in a real cycle: instance created, **`Synced`**/**`Healthy`**, then removed via this role. The namespace terminated cleanly **on the first attempt**, without any manual intervention, unlike the previous attempt (manual removal of everything at once), which required manual finalizer stripping.

---

## ⚙️ Key variables

| Variable | Required? | Description |
|---|---|---|
| **`acm_argocd_instances_cleanup`** | ✅ | List of instance objects to remove. Each object has **`name`**, **`namespace`**, and optionally **`managed_namespaces`** (list of **`{name: ...}`** dicts). See the command examples below for the expected format. |
| **`acm_argocd_instance_cleanup_confirm`** | ✅ | Safety gate. Must be explicitly set to **`true`**. The playbook refuses to proceed without it. |
| **`acm_argocd_instance_cleanup_dry_run`** | No (default **`false`**) | When **`true`**, simulates the entire pipeline via **`check_mode`**/**`diff`**: the API server validates changes but nothing is persisted. |
| **`acm_argocd_instance_cleanup_name`** / **`_namespace`** | No | Per-instance overrides derived from the **`acm_argocd_instances_cleanup`** list. Set automatically from each list entry; no need to pass these directly unless overriding a single instance run. |
| **`acm_argocd_instance_cleanup_managed_namespaces`** | No | Same list used during creation (**`acm_argocd_instance_setup_managed_namespaces`**). The role does not attempt to guess which namespaces the instance managed. |
| **`acm_argocd_instance_cleanup_remove_managed_namespaces`** | No (default **`true`**) | When **`false`**, removes only the GitOps infrastructure while preserving already deployed workloads. |

```bash
# Dry-run first (recommended)
ansible-playbook playbooks/cleanup-argocd-instance.yml \
  -e k8s_target_context="acm-primary-hub-sa" \
  -e acm_argocd_instance_cleanup_confirm=true \
  -e acm_argocd_instance_cleanup_dry_run=true \
  -e '{"acm_argocd_instances_cleanup": [{"name": "my-instance", "namespace": "my-ns",
       "managed_namespaces": [{"name": "app-a"}]}]}'

# Actual execution
ansible-playbook playbooks/cleanup-argocd-instance.yml \
  -e k8s_target_context="acm-primary-hub-sa" \
  -e acm_argocd_instance_cleanup_confirm=true \
  -e '{"acm_argocd_instances_cleanup": [{"name": "my-instance", "namespace": "my-ns",
       "managed_namespaces": [{"name": "app-a"}]}]}'
```

---

## ✅ Expected outcome

A successful run removes all of the following from the target Hub cluster for each instance in the list:

- All **`Application`** objects in the instance namespace (processed by the running **`application-controller`** so finalizers are released cleanly).
- The **`ApplicationSet`** in the instance namespace.
- Pre-created managed namespaces, if listed in **`managed_namespaces`** and **`remove_managed_namespaces: true`**.
- The **`ConsoleLink`** for the instance (if one was created during setup).
- The **`ClusterRoleBinding`** that granted **`cluster-admin`** to the instance's application controller SA.
- The ArgoCD CR in the instance namespace.
- The instance namespace itself, reaching **`Terminating → gone`** without manual intervention.

The OpenShift GitOps Operator (Subscription/CSV/OperatorGroup) and any other ArgoCD instances on the cluster are untouched.

---

## 🔄 Rollback after partial cleanup

If the cleanup is interrupted mid-run and a namespace is stuck in **`Terminating`**:

1. Check for remaining Application finalizers: **`oc get applications -n <instance-ns> -o json | jq '.items[].metadata.finalizers'`**
2. If finalizers remain, the **`application-controller`** may already be gone. Remove them manually:
   **`oc patch application/<name> -n <instance-ns> --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'`**
3. If the namespace itself has a finalizer: follow [*`docs/runbook/break-glass.md`*](../../docs/runbook/break-glass.md).
4. Re-run the cleanup role after clearing any stuck finalizers; it will skip already-removed objects.

To re-provision a removed instance, run [*`roles/acm_argocd_instance_setup`*](../acm_argocd_instance_setup) with the same variables.

---

Created and maintained by [Diego Felipe Mateus](https://github.com/dfmateus). See [CONTRIBUTORS.md](../../CONTRIBUTORS.md) for the list of contributors.
