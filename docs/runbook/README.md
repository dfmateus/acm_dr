# Runbook Index: ACM DR Operations

Operational runbooks for incident response and planned maintenance. Each runbook covers a specific failure mode or operation with a diagnosis procedure, recovery steps, and rollback path.

---

## When to use which runbook

```mermaid
%%{init: {"theme": "base", "themeVariables": {"lineColor": "#555555"}, "flowchart": {"htmlLabels": true}}}%%
flowchart TB
    classDef primary   fill:#3f9c35,stroke:#357a2e,color:#fff,font-weight:bold
    classDef header    fill:#06c,stroke:#0055b3,color:#fff,font-weight:bold
    classDef decision  fill:#f5f5f5,stroke:#aaaaaa,color:#151515
    classDef warn      fill:#fcce9a,stroke:#e0aa70,color:#151515,font-weight:bold
    START["Operator observes a problem"]:::header
    Q1{"Is the failover pipeline<br/>stuck at Stage 03 Restore?"}:::decision
    A1["<b>stage03-restore-hangs.md</b><br/>OADP/Velero diagnosis and recovery"]:::primary
    Q2{"Is there a stuck namespace or<br/>ManagedCluster in Terminating state?"}:::decision
    A2["<b>break-glass.md</b><br/>force-purge with finalizer removal"]:::primary
    Q3{"Did a SA token expire<br/>or does kubectl return 401?"}:::decision
    A3["<b>sa-token-rotation.md</b><br/>provision new token + update AAP cred"]:::primary
    Q4{"Does BackupSchedule show<br/>phase=BackupCollision?"}:::decision
    A4["<b>backup-collision-recovery.md</b><br/>delete+recreate BackupSchedule CR"]:::primary
    Q5{"Are ArgoCD Applications OutOfSync<br/>or Unknown after failover?"}:::decision
    A5["<b>argocd-sync-failure.md</b><br/>re-run JT5 or patch the cluster-secret"]:::primary
    Q6{"Did a PrometheusRule alert fire?<br/>(backup stale, BSL unavailable, pod unhealthy)"}:::decision
    A6["Check alert description and runbook link<br/>in the alert annotation.<br/>RHACM Business Continuity docs"]:::primary
    Q7{"Does auto-import-account MSA show<br/>TokenReportFailed after failover?"}:::decision
    A7["<b>acm-38215-auto-import-account.md</b><br/>⚠️ Known ACM bug - Spokes stay AVAILABLE<br/>No action required until upgrade to 2.17.1"]:::primary
    END["Escalate to Ansible role maintainer<br/>with AAP job ID and Stage output"]:::warn
    START --> Q1
    Q1 -->|Yes| A1
    Q1 -->|No| Q2
    Q2 -->|Yes| A2
    Q2 -->|No| Q3
    Q3 -->|Yes| A3
    Q3 -->|No| Q4
    Q4 -->|Yes| A4
    Q4 -->|No| Q5
    Q5 -->|Yes| A5
    Q5 -->|No| Q6
    Q6 -->|Yes| A6
    Q6 -->|No| Q7
    Q7 -->|Yes| A7
    Q7 -->|No| END
```

---

## Runbooks

| File | Covers | Severity |
|------|--------|----------|
| [stage03-restore-hangs.md](stage03-restore-hangs.md) | OADP Restore stuck or failed during failover Stage 03 | ❌ Critical |
| [sa-token-rotation.md](sa-token-rotation.md) | Long-lived ServiceAccount token expired (kubectl 401) | ❌ Critical |
| [break-glass.md](break-glass.md) | Namespace or ManagedCluster stuck in Terminating state | ⚠️ High |
| [backup-collision-recovery.md](backup-collision-recovery.md) | BackupSchedule shows phase=BackupCollision, Hub stops writing backups | ⚠️ High |
| [argocd-sync-failure.md](argocd-sync-failure.md) | ArgoCD Applications stuck in OutOfSync or Unknown after failover | ⚠️ High |
| [acm-38215-auto-import-account.md](acm-38215-auto-import-account.md) | `auto-import-account` MSA shows `TokenReportFailed` after failover (ACM < 2.17.1) | ⚠️ Informational |

---

## General principles

- **Check the AAP job output first.** Every stage writes **`✅`**/**`❌`**/**`⚠️`** prefixed debug messages. The failing task name and the targeted cluster context appear in the task header. Start there before running any manual command.
- **Dry-run before acting.** Most recovery steps have a **`--dry-run=server -o yaml`** or **`acm_dr_failover_manager_dry_run=true`** equivalent. Run it first.
- **Document what you ran.** During an incident, paste every command you execute and its output into the incident ticket. The timeline is reconstructable only if the commands are recorded.
- **Never bypass safety guards to make a test pass.** If a Stage 00 assertion blocks you, understand why before bypassing it. The guards exist because the condition they check has caused real outages.

---

## RTO targets (lab environment)

| Operation | Target | Notes |
|-----------|--------|-------|
| DR failover (production run) | 30 minutes | Includes Spoke reconnection |
| DR failover (dry-run) | 10 minutes | No Restore, no Spoke wait |
| SA token rotation + AAP update | 15 minutes | Per cluster |
| Stuck namespace recovery | 5 minutes | Via break-glass script |
| Stage 03 Restore recovery | 60 minutes | Depends on backup size |

---

## External references

- [RHACM 2.17 Business Continuity](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.17/html-single/business_continuity/index): official DR documentation
- [KCS 7039710: ManagedServiceAccount token restore failure](https://access.redhat.com/solutions/7039710): MSA token purge after OADP Restore
- [KCS 5950901: Graceful managed cluster removal](https://access.redhat.com/solutions/5950901): Spoke detach procedure
