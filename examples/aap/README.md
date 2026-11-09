# CasC: Controller as Code (AAP)

Machine-readable YAML definitions for every AAP object this collection needs. Import them once on a fresh AAP instance and every Job Template, Workflow, Credential Type, and Schedule is ready without touching the UI.

For the full parameter reference and survey documentation, see [*`docs/aap/aap.md`*](../../docs/aap/aap.md).

---

## Files in this directory

| File | AAP object type | Notes |
| --- | --- | --- |
| [*`controller_organizations.yml`*](controller_organizations.yml) | Organization | Import first. All other objects depend on it. |
| [*`controller_execution_environments.yml`*](controller_execution_environments.yml) | Execution Environment | References the EE image registry |
| [*`controller_inventories.yml`*](controller_inventories.yml) | Inventory + Host | Defines the localhost inventory and host entry |
| [*`controller_projects.yml`*](controller_projects.yml) | Project | Points to the git repo (**`file:///tmp/acm_dr_orchestrator.git`** in lab) |
| [*`controller_credential_types.yml`*](controller_credential_types.yml) | Credential Type (x7) | Custom types for Hub/Spoke SA tokens and GitHub PAT |
| [*`controller_credentials.yml`*](controller_credentials.yml) | Credential (x7+) | REDACTED placeholders; fill before importing |
| [*`controller_job_templates.yml`*](controller_job_templates.yml) | Job Template (x8) | All playbook JTs with surveys |
| [*`controller_workflow_job_templates.yml`*](controller_workflow_job_templates.yml) | Workflow Job Template (x5) | WF-01 through WF-05 including Approval Nodes |
| [*`controller_schedules.yml`*](controller_schedules.yml) | Schedule (x2) | Weekly DR Drill and Monthly Lab Rebuild (disabled by default) |
| [*`controller_notifications.yml`*](controller_notifications.yml) | Notification Template (x2) | Slack notifications for failover and lab ops events |

---

## Import order

AAP objects reference each other by name, so the import order matters. Always import in this sequence:

```
1. organizations          - creates the org that everything belongs to
2. execution_environments - registers the EE image
3. inventories            - creates inventory + localhost host
4. projects               - creates the project and triggers an initial SCM sync
5. credential_types       - defines custom input schemas before credentials use them
6. credentials            - fill REDACTED placeholders first (see below)
7. job_templates          - references org, project, inventory, EE, and credential types
8. workflow_job_templates - references job templates by name
9. schedules              - references workflow and job templates by name
10. notifications         - attach to job/workflow templates separately in the UI or via API
```

---

## How to import: **`infra.controller_configuration`**

```bash
# Install the import collection (one-time)
ansible-galaxy collection install infra.controller_configuration

# Set your AAP endpoint and credentials
export CONTROLLER_HOST=https://aap.example.com
export CONTROLLER_USERNAME=admin
export CONTROLLER_PASSWORD=changeme

# Common extra-vars (adjust to your environment)
COMMON="-e controller_hostname=${CONTROLLER_HOST} \
        -e controller_username=${CONTROLLER_USERNAME} \
        -e controller_password=${CONTROLLER_PASSWORD} \
        -e aap_organization=Default \
        -e aap_project=ACM-DR-Orchestrator \
        -e aap_inventory='ACM DR - LAB' \
        -e aap_execution_environment=acm-dr-orchestrator-ee"

# Import each object type in order
ansible-playbook ${COMMON} -e @examples/aap/controller_organizations.yml          infra.controller_configuration.organizations
ansible-playbook ${COMMON} -e @examples/aap/controller_execution_environments.yml infra.controller_configuration.execution_environments
ansible-playbook ${COMMON} -e @examples/aap/controller_inventories.yml            infra.controller_configuration.inventories
ansible-playbook ${COMMON} -e @examples/aap/controller_inventories.yml            infra.controller_configuration.hosts
ansible-playbook ${COMMON} -e @examples/aap/controller_projects.yml               infra.controller_configuration.projects
ansible-playbook ${COMMON} -e @examples/aap/controller_credential_types.yml       infra.controller_configuration.credential_types
ansible-playbook ${COMMON} -e @examples/aap/controller_credentials.yml            infra.controller_configuration.credentials
ansible-playbook ${COMMON} -e @examples/aap/controller_job_templates.yml          infra.controller_configuration.job_templates
ansible-playbook ${COMMON} -e @examples/aap/controller_workflow_job_templates.yml infra.controller_configuration.workflow_job_templates
ansible-playbook ${COMMON} -e @examples/aap/controller_schedules.yml              infra.controller_configuration.schedules
ansible-playbook ${COMMON} -e @examples/aap/controller_notifications.yml          infra.controller_configuration.notification_templates
```

> **Lab shortcut**: when using a local git repo inside the AAP controller pod (instead of a remote SCM URL), use the 4-step bare-repo sync procedure (init, tar, push via python3 stdin, verify) to push code changes before triggering a project sync. See the [AAP setup guide](../../docs/aap/aap-setup.md) for details.

---

## Placeholder variables

The YAML files use Jinja2 variables that must be resolved at import time via **`-e`** flags. These four appear in every object type:

| Variable | Purpose | Example value |
| --- | --- | --- |
| **`aap_organization`** | Organization name | **`Default`** |
| **`aap_project`** | Project name (this repo) | **`ACM DR Collection (main)`** |
| **`aap_inventory`** | Localhost inventory name | **`ACM DR - LAB`** |
| **`aap_execution_environment`** | EE name | **`EE - ACM DR 1.0.0`** |

---

## Credentials: fill REDACTED placeholders before importing

[*`controller_credentials.yml`*](controller_credentials.yml) contains placeholder values (**`REPLACE_WITH_...`**) for every sensitive field. Fill them using **`-e`** extra-vars at import time or by editing a local copy that is **not committed to git**:

```bash
# Example: import credentials with real values via extra-vars
ansible-playbook ${COMMON} \
  -e @examples/aap/controller_credentials.yml \
  -e cred_source_hub_host=https://api.hub-a.example.com:6443 \
  -e cred_source_hub_token=<SA_TOKEN> \
  -e cred_source_hub_context=acm-primary-hub-sa \
  infra.controller_configuration.credentials
```

Never commit real tokens, passwords, or kubeconfig content to this directory. All credential values must come from environment variables, a vault, or injected extra-vars at import time.

### Workflow-level placeholders (WF-03)

**`controller_workflow_job_templates.yml`** also has environment-specific placeholders that must be replaced before WF-03 (**`WF - ACM DR - LAB - Full Lab Rebuild`**) can run. The affected nodes:

| Node | Variable | Placeholder |
|---|---|---|
| **`setup-primary-hub`** | **`acm_dr_hub_setup_azure_resource_group`** | **`REPLACE_WITH_AZURE_RESOURCE_GROUP`** |
| **`setup-primary-hub`** | **`acm_dr_hub_setup_azure_storage_account_name`** | **`REPLACE_WITH_AZURE_STORAGE_ACCOUNT`** |
| **`onboard-spokes`** | **`acm_dr_spoke_manager_cluster_name`** | **`REPLACE_WITH_SPOKE_CLUSTER_NAME`** |
| **`setup-passive-hub`** | **`acm_dr_hub_setup_azure_resource_group`** | **`REPLACE_WITH_AZURE_RESOURCE_GROUP`** |
| **`setup-passive-hub`** | **`acm_dr_hub_setup_azure_storage_account_name`** | **`REPLACE_WITH_AZURE_STORAGE_ACCOUNT`** |

Edit the **`extra_data`** blocks in [*`controller_workflow_job_templates.yml`*](controller_workflow_job_templates.yml) directly before importing, or pass the values as extra-vars at launch time through the AAP survey.

---

## Maintenance: standardizing object names

After import, object names and descriptions may drift from the convention if updates are applied manually through the AAP UI. [*`examples/playbooks/configure-aap-objects.yml`*](../configure-aap-objects.yml) renames all ACM DR objects to the canonical naming pattern and updates their descriptions without touching credentials or secrets.

```bash
export CONTROLLER_HOST="https://aap-aap.apps.<cluster>.aroapp.io"
export CONTROLLER_PASSWORD="<admin password>"

# Preview every rename without applying (check mode)
ansible-playbook examples/playbooks/configure-aap-objects.yml --check -v

# Apply renames and description updates
ansible-playbook examples/playbooks/configure-aap-objects.yml -v
```

For the full object inventory and naming convention, see [*`docs/aap/aap.md: Section 11`*](../../docs/aap/aap.md).
