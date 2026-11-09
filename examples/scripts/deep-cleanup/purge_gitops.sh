#!/usr/bin/env bash
# ==============================================================================
# Script: purge_gitops.sh
# Purpose: Full purge of the Red Hat OpenShift GitOps Operator,
#          unlocking Applications, CSVs, Finalizers, and Namespaces.
# Maintained by: Diego Felipe Mateus (https://github.com/dfmateus)
# ==============================================================================

set -euo pipefail

OPERATOR_NS="openshift-gitops-operator"
TARGET_NAMESPACES="${1:-openshift-gitops-operator openshift-gitops openshift-gitops-acm openshift-gitops-appdemo acm-policies}"

echo "======================================================================"
echo "🚀 [RHOCP LAB] Full Purge of Red Hat OpenShift GitOps"
echo "📦 Base Operator Namespace: ${OPERATOR_NS}"
echo "======================================================================"

# 1. Prerequisite validation
if ! command -v oc &> /dev/null; then
    echo "❌ [ERROR] The 'oc' binary was not found in the PATH."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ [ERROR] The 'jq' binary was not found in the PATH."
    exit 1
fi

# 2. Unlock and Delete Argo CD Application and ApplicationSet Instances
echo ""
echo "⏳ [1/7] Unlocking and removing Applications and ApplicationSets (argoproj.io)..."
for crd_kind in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io argocds.argoproj.io gitopsservices.pipelines.openshift.io; do
    echo "   🔍 Processing resources of type: ${crd_kind}"
    
    # Get all resources explicitly by Namespace and Name
    oc get ${crd_kind} -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null | while read -r ns name; do
        if [ -n "${name}" ]; then
            echo "   ⚠️ [PATCH & DELETE] Removing finalizers from resource: ${name} (Namespace: ${ns})"
            # Apply patch clearing the finalizers list
            oc patch ${crd_kind} "${name}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
            oc delete ${crd_kind} "${name}" -n "${ns}" --force --grace-period=0 2>/dev/null || true
        fi
    done
done

# 3. Remove OLM Subscriptions and InstallPlans
echo ""
echo "⏳ [2/7] Uninstalling OLM Subscriptions and InstallPlans..."
oc delete subscription --all -n "${OPERATOR_NS}" --ignore-not-found || true
oc delete installplan --all -n "${OPERATOR_NS}" --ignore-not-found || true

# 4. Unlock and delete stuck CSVs (Forced Finalizer Removal)
echo ""
echo "⏳ [3/7] Unlocking and purging ClusterServiceVersions (CSVs)..."
CSVS=$(oc get csv -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep gitops || true)

if [ -n "${CSVS}" ]; then
    for item in ${CSVS}; do
        ns=$(echo "${item}" | cut -d'/' -f1)
        csv=$(echo "${item}" | cut -d'/' -f2)
        echo "   🔓 Removing finalizers from CSV: ${csv} (Namespace: ${ns})"
        oc patch csv "${csv}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        oc delete csv "${csv}" -n "${ns}" --force --grace-period=0 --ignore-not-found || true
    done
else
    echo "   ℹ️ No GitOps CSV found."
fi

# 5. Remove OperatorGroups in all involved namespaces
echo ""
echo "⏳ [4/7] Removing OperatorGroups..."
for ns in ${TARGET_NAMESPACES}; do
    oc delete operatorgroup --all -n "${ns}" --ignore-not-found 2>/dev/null || true
done

# 6. Clean up ConsolePlugins, Webhooks, and Global RBAC
echo ""
echo "⏳ [5/7] Cleaning up Webhooks, ConsolePlugins, and Cluster-Scoped RBAC..."
oc delete consoleplugin console-plugin-gitops --ignore-not-found || true
oc delete validatingwebhookconfiguration -l app.kubernetes.io/part-of=argocd --ignore-not-found || true
oc delete mutatingwebhookconfiguration -l app.kubernetes.io/part-of=argocd --ignore-not-found || true
oc delete validatingwebhookconfiguration openshift-gitops-webhook-config --ignore-not-found || true
oc delete mutatingwebhookconfiguration openshift-gitops-webhook-config --ignore-not-found || true
oc delete clusterrole -l app.kubernetes.io/part-of=argocd --ignore-not-found || true
oc delete clusterrolebinding -l app.kubernetes.io/part-of=argocd --ignore-not-found || true

# 7. Remove Custom Resource Definitions (CRDs)
echo ""
echo "⏳ [6/7] Purging ArgoCD and GitOps Custom Resource Definitions (CRDs)..."
CRDS=$(oc get crd --no-headers 2>/dev/null | grep -E 'argoproj.io|gitops' | awk '{print $1}' || true)
if [ -n "${CRDS}" ]; then
    for crd in ${CRDS}; do
        echo "   🗑️ Removing finalizers and deleting CRD: ${crd}"
        oc patch crd "${crd}" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        oc delete crd "${crd}" --ignore-not-found --timeout=15s || true
    done
else
    echo "   ℹ️ No related CRD found."
fi

# 8. Delete and advanced Namespace unlocking (RAW API)
echo ""
echo "⏳ [7/7] Purging Namespaces and fixing 'Terminating' states..."
for ns in ${TARGET_NAMESPACES}; do
    if oc get namespace "${ns}" &>/dev/null; then
        echo "   🗑️ Requesting deletion of namespace: ${ns}"
        oc delete namespace "${ns}" --wait=false || true
        sleep 3
        
        STATUS=$(oc get namespace "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
        if [ "${STATUS}" == "Terminating" ]; then
            echo "   ⚠️ [ADVANCED PATCH] Namespace ${ns} stuck in 'Terminating'. Forcing cleanup via REST API..."
            # Force removal of finalizers in the namespace spec directly on the /finalize endpoint
            oc get namespace "${ns}" -o json | jq '.spec.finalizers = []' | oc replace --raw "/api/v1/namespaces/${ns}/finalize" -f - &>/dev/null || true
        fi
    fi
done

# Final Verification
echo ""
echo "🔍 Checking residual cluster state..."
REMAINING_APPS=$(oc get applications.argoproj.io -A 2>/dev/null || true)
REMAINING_CSV=$(oc get csv -A 2>/dev/null | grep gitops || true)
REMAINING_NS=$(oc get ns 2>/dev/null | grep -E "openshift-gitops|acm-policies" || true)

if [ -z "${REMAINING_APPS}" ] && [ -z "${REMAINING_CSV}" ] && [ -z "${REMAINING_NS}" ]; then
    echo "======================================================================"
    echo "✅ [PURGE SUCCESS] Cluster fully cleaned of GitOps remnants!"
    echo "======================================================================"
else
    echo "⚠️ [WARNING] Residual resources still detected:"
    [ -n "${REMAINING_APPS}" ] && echo "  - Applications: ${REMAINING_APPS}"
    [ -n "${REMAINING_CSV}" ] && echo "  - CSVs: ${REMAINING_CSV}"
    [ -n "${REMAINING_NS}" ] && echo "  - Namespaces: ${REMAINING_NS}"
fi
