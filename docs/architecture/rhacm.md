# What is Red Hat Advanced Cluster Management for Kubernetes?

Red Hat® Advanced Cluster Management for Kubernetes offers end-to-end management, visibility, and
control of your entire fleet from a single console, with operational policies built in. Extend the
value of Red Hat OpenShift® by deploying apps, managing multiple clusters, and enforcing policies
across multiple clusters deployed to datacenter, cloud, and edge environments. Red Hat Advanced
Cluster Management for Kubernetes is included with Red Hat OpenShift Platform Plus.

---

## What RHACM provides

| Capability | Description |
|:---|:---|
| **Multi-Cluster Lifecycle Management** | Create, import, upgrade, and decommission OpenShift and Kubernetes clusters across hybrid and multi-cloud environments from a single Hub. |
| **Governance, Risk, and Compliance (GRC)** | Define and enforce policies at fleet scale (configuration standards, security baselines, certificate management, and namespace quotas) with automatic remediation. |
| **Application Lifecycle** | Deploy and manage applications consistently across clusters using Subscriptions, Placements, and ApplicationSets integrated with GitOps (Argo CD / OpenShift GitOps). |
| **Observability** | Unified metrics, alerts, and dashboards across all managed clusters via an integrated Thanos-based Observability stack, with fleet-wide health visibility from the Hub console. |
| **Search and Discovery** | Index and search Kubernetes resources across the entire fleet in real time (Pods, Deployments, Nodes, Policies, and custom resources) from a single query interface. |
| **Cluster Backup and Restore** | Protect the Hub's fleet state (ManagedClusters, Policies, Applications, Placements, Channels) via OADP-based backup and restore, enabling Disaster Recovery between Hub pairs. |

---

## How this automation suite relates to RHACM

This repository (the **Multi-Cluster DR Orchestrator**) automates the **Backup and Restore** and
**Disaster Recovery** capabilities of RHACM at scale. Specifically, it:

* **Orchestrates Hub-to-Hub failover and failback** using RHACM's native OADP integration, with
  split-brain prevention, known-bug mitigations ([KCS 7039710](https://access.redhat.com/solutions/7039710), [KCS 5950901](https://access.redhat.com/solutions/5950901)), and automated fleet
  reconnection.
* **Manages Spoke lifecycle** (onboarding, reconnection, detachment) across any Kubernetes
  distribution through RHACM's ManagedCluster and auto-import APIs.
* **Provisions Hub infrastructure** (MultiClusterHub, Observability, GitOps, OADP
  DataProtectionApplication) to establish DR-ready Hub pairs.
* **Enables Planned Maintenance Switchover**, using the DR pipeline as a zero-downtime upgrade
  strategy for Hub clusters.
* **Supports DR Readiness Drills**: dry-run rehearsal of the full failover pipeline against real
  clusters without applying changes.

For full operational details, see the [main README](../../README.md).

---

## Official Red Hat resources

| Resource | Link |
|:---|:---|
| **Product Page** | [Red Hat Advanced Cluster Management for Kubernetes](https://www.redhat.com/en/technologies/management/advanced-cluster-management) |
| **Datasheet** | [Red Hat Advanced Cluster Management for Kubernetes: Datasheet](https://www.redhat.com/en/resources/advanced-cluster-management-kubernetes-datasheet) |
| **Product Documentation** | [RHACM Documentation on Red Hat Docs](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes) |
| **Backup and Restore Guide** | [RHACM Backup and Restore Framework](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes) |
| **Red Hat Knowledgebase** | [KCS 7039710: ManagedServiceAccount token restore failure](https://access.redhat.com/solutions/7039710) |
| **Red Hat Knowledgebase** | [KCS 5950901: Graceful ManagedCluster detach](https://access.redhat.com/solutions/5950901) |
