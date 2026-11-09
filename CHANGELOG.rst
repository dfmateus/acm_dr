=======================================
dfmateus.acm_dr Release Notes
=======================================

.. contents:: Topics

v1.0.0
======

Release Summary
---------------

Initial release of the RHACM Multi-Cluster Disaster Recovery automation suite
as an Ansible Galaxy collection. Covers DR failover and failback for RHACM 2.10+
across ARO Classic, ROSA Classic, ROSA HCP, and vanilla Kubernetes, with full
AAP 2.7 Gateway integration.

New Roles
---------

- ``acm_dr_failover_manager``: 9-stage DR failover/failback engine (preflight,
  fleet discovery, logical fencing, pre-restore cleanup, Restore activation,
  Spoke sanitization + reconnect, fleet protection, old Hub detach, postflight
  compliance audit). Supports dry-run, skip-gates, and planned maintenance
  failover with version compatibility checks.
- ``acm_dr_spoke_manager``: distribution-agnostic Spoke lifecycle
  (``onboard``, ``prep``, ``detach``). Implements KCS 7039710 MSA token purge,
  KCS 5950901 klusterlet cleanup, Zero-Trust ServiceAccount model, and
  Operation C mirrored token fallback for fleet reconnect after restore.
- ``acm_dr_hub_setup``: Hub infrastructure provisioning for Azure (ARO) and
  AWS (ROSA). Deploys MCH, OADP/DPA/BackupSchedule, Observability, GitOps,
  and automation RBAC. Configures active and passive Hub roles.
- ``acm_dr_hub_cleanup``: scoped Hub decommissioning with safety gate
  (``confirm=true`` required). Staged teardown with break-glass finalizer
  remediation for stuck Terminating namespaces.
- ``acm_dr_cluster_onboard``: bootstrap ServiceAccount + ClusterRoleBinding +
  non-expiring token Secret on any cluster. Self-registers the resulting
  credential into AAP via REST API when the AAP Automation Token credential
  is attached.
- ``acm_dr_msa_provisioner``: ManagedServiceAccount CR + ManifestWork
  ClusterRoleBinding on the Hub for a named Spoke. Waits for the klusterlet
  to write the auto-rotated token Secret back to the Hub namespace.
- ``acm_dr_readiness_check``: read-only pre-failover healthcheck. Validates
  BackupSchedule phase, BSL availability, backup age (RPO), Spoke count,
  and passive Restore presence.
- ``acm_dr_kubeconfig_resolver``: runtime kubeconfig assembly from AAP
  credentials (per-cluster env var prefix or monolithic fleet Secret).
  Detects ARO/ROSA HCP topology via Infrastructure CR.
- ``acm_argocd_instance_setup``: parametric ArgoCD instance provisioning
  with GitOps Operator, RBAC, repository Secret, RHACM integration, and
  ConsoleLink.
- ``acm_argocd_instance_cleanup``: ArgoCD instance removal (dry-run by
  default). Strips ArgoCD Application finalizers before removing controller
  pods to prevent stuck Terminating namespaces.
- ``acm_dr_upgrade_manager``: planned maintenance channel upgrade for ACM
  MultiClusterHub. Patches OLM Subscription, waits for MCH Running phase,
  enforces version compatibility matrix (RHACM 2.10-2.17, OCP 4.13-4.23).

Major Features
--------------

**Failover safety and idempotency:**

- Logical fencing in Stage 02 polls ``BackupSchedule.status.phase`` until
  ``BackupSchedulePaused`` before proceeding - no fixed delay, no silent
  pass-through if the ACM operator rejects the patch.
- Explicit backup resolution by source cluster ID (``ClusterVersion`` UID +
  ``backup-cluster`` label) avoids the ``latest`` ambiguity when two Hub
  pairs share the same storage account.
- Assert gate in Stage 03 blocks Restore CR creation if any backup category
  resolved to ``latest`` (configurable with ``allow_latest_backup=true``).
- Automatic rollback when Stage 03 Restore fails or times out: re-enables
  ``BackupSchedule`` on the source Hub, polls until ``Enabled``, and deletes
  the failed Restore CR before surfacing the failure. Configurable with
  ``rollback_on_restore_failure`` (default ``true``).
- BackupCollision auto-resolution in Stage 05 (expected after failback when
  storage carries backups from the prior leader).

**Operation C - unreachable Spoke reconnect:**

- During Spoke onboarding, ``acm_dr_spoke_manager`` mirrors the permanent
  SA token and API host to a Hub-side Secret with the OADP backup label.
  The OADP BackupSchedule replicates this Secret to every passive Hub.
- Stage 07 reads these Secrets to reconnect Spokes missing from the restored
  fleet kubeconfig without manual intervention.
- Onboarding now asserts that ``ACM_DR_SPOKE_TOKEN`` is set when
  ``hub_token_mirror_enabled=true``. Override with
  ``allow_missing_spoke_credential=true`` only when the Spoke is guaranteed
  to appear in the fleet kubeconfig after restore.

**Webhook notifications for internal events (opt-in):**

- Attach the ``ACM DR - Notification Webhook`` credential to send alerts for:
  BackupCollision auto-resolved (warning), Operation C activated for Spokes
  (warning), and Spokes without any fallback credential (critical).
- Supports Slack, Microsoft Teams Adaptive Card, and generic JSON formats.
  Non-blocking: absent credential is a silent no-op.

**Multi-hub topology:**

- ``additional_passive_hubs`` list enables 3+ Hub topologies. After failover,
  additional passive Hubs' sync Restore CRs are recycled automatically so
  they pick up backups from the new leader.

**Version compatibility and planned maintenance failover:**

- Preflight checks OCP and RHACM versions on both Hubs, enforces a
  configurable minor-version gap limit, and validates Spoke compatibility
  against a built-in RHACM-to-OCP matrix.
- ``target_acm_version`` enables Planned Maintenance Failover upgrade
  validation before patching the source Hub.

**MSA Spoke verifier (opt-in Stage 07b):**

- After fleet reconnect, Stage 07b reads MSA tokens from the passive Hub and
  probes each Spoke API server directly from the Execution Environment.
  Detects NSG-level asymmetry that Hub-side ManagedCluster status cannot see.

**Zero-Trust ServiceAccount model:**

- Every cluster carries a non-expiring ``ansible-dr-orchestrator`` SA token
  in a dedicated namespace. ``acm_dr_kubeconfig_resolver`` assembles a
  synthetic kubeconfig at runtime without storing credentials on disk.

**AAP 2.7 Gateway support:**

- All REST API calls use the ``/api/controller/v2/`` path.
- CasC import (``infra.controller_configuration`` 3.x) with known gotchas
  resolved: variable name changes, ``!unsafe`` for credential injector
  templates, ``simplified_workflow_nodes``, ``multiplechoice`` survey type,
  schedule rrule ``BYSETPOS`` format, and ``INTERVAL`` requirement.
- Approval gate introspection via ``source_workflow_job`` (not
  ``workflow_job``) and WFT node ``unified_job_type`` filter.

**Code quality:**

- All 11 roles have ``argument_specs.yml`` with typed parameters and
  descriptions.
- Namespace finalizer removal unified to a single ``jq`` pipeline pattern
  across all roles with correct ``changed_when`` (stdout length, not rc).
- Webhook notification helper (``tasks/common/notify_event.yml``) reusable
  across stages without coupling to the AAP notification JT.
- ``ansible-lint --profile production`` passes with 0 failures across all
  187 task files.

Bugfixes
--------

- ``acm_dr_failover_manager`` Stage 06 task 6.1.6: ``changed_when``
  simplified to ``stdout | length > 0``; the previous ``rc == 0`` check
  was always true due to ``|| true`` in the pipeline.
- ``acm_dr_hub_cleanup`` D.7d-e: consolidated two-step namespace finalizer
  remediation (``oc get`` + ``python3``) into a single ``jq`` pipeline.
  The previous ``changed_when: item.rc == 0`` referenced the GET result
  instead of the REPLACE result, incorrectly reporting changed even when
  the replace did not run.
- ``acm_dr_spoke_manager`` task 1.2.0a: ``changed_when`` corrected to
  ``stdout | length > 0``; ``rc`` was always 0 due to ``|| true``.
- ``acm_dr_spoke_manager`` task 1.6.1: elevated from ``debug`` (silent
  warning) to ``ansible.builtin.assert`` to prevent silent onboarding of
  Spokes without Operation C fallback coverage.
- ``acm_dr_failover_manager`` Stage 04 task 4.1.1a: added
  ``changed_when: false`` to pure-poll shell task that was always reporting
  ``changed=true``.
- ``acm_dr_hub_setup`` defaults: ``azure_location`` now reads
  ``AZURE_LOCATION`` env var with ``eastus`` as fallback. Previously
  hardcoded without an override path.
- ``acm_dr_hub_setup`` preflight: emits an explicit ``debug`` warning when
  ``ACM_CHANNEL`` env var is absent and the MCH channel falls back to the
  built-in default.

Known Limitations
-----------------

- Molecule test coverage is limited to a single offline scenario
  (``molecule/default/``). Role-level flow tests for
  ``acm_dr_failover_manager`` and ``acm_dr_spoke_manager`` are planned for
  a future release.
- ROSA HCP storage provisioning uses the generic AWS path. ROSA-specific STS
  and managed OIDC handling is planned.
- No automatic rollback for failures in Stage 07 (Spoke sanitize) or Stage
  08 (postflight). Manual intervention is required if these stages fail.
