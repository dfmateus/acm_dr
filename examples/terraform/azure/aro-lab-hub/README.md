# ARO Lab Hub - Terraform Provisioning

Terraform variable files for provisioning ARO Hub and Spoke clusters as a DR lab environment.
These templates work with the [terraform-aro](https://github.com/rh-mobb/terraform-aro) project
from Red Hat Cloud Experts - see the [ARO Terraform install guide](https://cloud.redhat.com/experts/aro/terraform-install/)
for full background.

Each cluster has its own subdirectory containing a single **`.tfvars.example`** file:

```
aro-lab-hub/
├── hub-01/
│   └── hub-01.tfvars.example          # Hub 01 - 10.0.0.0/20
├── hub-02/
│   └── hub-02.tfvars.example          # Hub 02 - 10.1.0.0/20
└── spoke-aroclassic-01/
    └── spoke-aroclassic-01.tfvars.example  # ARO Classic Spoke - 10.2.0.0/20
```

| Subdirectory | Cluster | VNet CIDR |
|---|---|---|
| **`hub-01/`** | Hub 01 - interchangeable active/passive role | **`10.0.0.0/20`** |
| **`hub-02/`** | Hub 02 - interchangeable active/passive role | **`10.1.0.0/20`** |
| **`spoke-aroclassic-01/`** | ARO Classic Spoke | **`10.2.0.0/20`** |

Neither hub is permanently "active" or "passive". Which one runs **BackupSchedule** and which one runs **Restore** depends on the current failover direction, managed by the collection.

## Adding more hubs (hub-03, hub-04, ...)

The DR pair (hub-01 + hub-02) is enough to start. Add more hubs only when the topology requires it (e.g., a third passive site for geo-redundancy). The template is identical for every additional hub - copy `hub-01/hub-01.tfvars.example`, adjust three values, and follow [**`docs/onboarding/add-new-hub.md`**](../../../../docs/onboarding/add-new-hub.md) to onboard it via AAP.

| Value to change | hub-01 | hub-03 example |
|---|---|---|
| `cluster_name` | `acmdr-lab-hub-01` | `acmdr-lab-hub-03` |
| `domain` | `acmdrlabhub01` | `acmdrlabhub03` |
| `aro_virtual_network_cidr_block` | `10.0.0.0/20` | `10.3.0.0/20` |
| `aro_control_subnet_cidr_block` | `10.0.0.0/23` | `10.3.0.0/23` |
| `aro_machine_subnet_cidr_block` | `10.0.2.0/23` | `10.3.2.0/23` |

VNet allocation: hub-01 = `10.0.x`, hub-02 = `10.1.x`, spoke = `10.2.x`, hub-03 = `10.3.x`, hub-04 = `10.4.x`, and so on. Keep each block a `/20` (4096 addresses) and verify there is no overlap with existing VNets in the Azure subscription before provisioning.

---

## Prerequisites

- **`terraform >= 1.5.0`**
- **`az`** CLI - logged in with **`az login --use-device-code`** using an account that has permission to create Service Principals (**`az ad sp create-for-rbac`**)
- **`jq`** (used by the wrapper script)
- Red Hat pull secret at **`.local/config/pull-secret.txt`** - download from [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret)
- The [terraform-aro](https://github.com/rh-mobb/terraform-aro) project cloned locally

---

## Setup steps

### 1. Clone terraform-aro and initialise providers

```bash
git clone https://github.com/rh-mobb/terraform-aro.git ~/Documents/RedHat/LAB/TERRAFORM/terraform-aro
cd ~/Documents/RedHat/LAB/TERRAFORM/terraform-aro
terraform init
```

**`terraform init`** downloads providers and modules into **`.terraform/modules/`**. It must run at
least once before the first **`terraform plan`**. The wrapper script re-runs it automatically
when modules are absent, but running it manually here avoids a confusing "Module not
installed" error if the project has never been initialised on this machine.

If you clone to a different path, set **`TERRAFORM_ARO_DIR`** before running the wrapper:

```bash
export TERRAFORM_ARO_DIR=/your/path/to/terraform-aro
```

### 2. Copy the tfvars templates

```bash
mkdir -p .local/terraform/acmdr-lab-hub-01
mkdir -p .local/terraform/acmdr-lab-hub-02
mkdir -p .local/terraform/acmdr-spoke-aroclassic-01

cp examples/terraform/azure/aro-lab-hub/hub-01/hub-01.tfvars.example \
   .local/terraform/acmdr-lab-hub-01/terraform.tfvars

cp examples/terraform/azure/aro-lab-hub/hub-02/hub-02.tfvars.example \
   .local/terraform/acmdr-lab-hub-02/terraform.tfvars

cp examples/terraform/azure/aro-lab-hub/spoke-aroclassic-01/spoke-aroclassic-01.tfvars.example \
   .local/terraform/acmdr-spoke-aroclassic-01/terraform.tfvars
```

The **`.local/`** directory is gitignored - no credentials or state will be committed.

### 3. Source credentials

```bash
source .local/cloud/azure/env-setup.sh   # sets SUBSCRIPTION, TENANT, CLIENT_ID, PASSWORD
az login --use-device-code         # user-level session required for SP creation
az account set --subscription "$SUBSCRIPTION"
```

### 4. Provision each cluster

Use the wrapper script. It handles workspace selection, plan, apply, and kubeconfig download automatically.

**Run clusters sequentially, not in parallel.** The **`terraform-aro`** project uses a local state backend. Terraform acquires a file lock on the state before any plan or apply, and a second concurrent invocation in the same directory fails immediately with **`Error acquiring the state lock`**. Run one cluster at a time and wait for it to finish before starting the next.

```bash
# Dry-run first (always) - no cluster is created
bash .local/azure/provision-aro-terraform.sh --cluster acmdr-lab-hub-01

# Apply - wait for each to finish before starting the next (local state lock)
bash .local/azure/provision-aro-terraform.sh --cluster acmdr-lab-hub-01 --apply
bash .local/azure/provision-aro-terraform.sh --cluster acmdr-lab-hub-02 --apply
bash .local/azure/provision-aro-terraform.sh --cluster acmdr-spoke-aroclassic-01 --apply
```

Each successful apply writes two files to **`.local/`**:

- **`kubeconfig-<cluster>-admin`** - admin kubeconfig
- **`kubeadmin-<cluster>.env`** - API URL, console URL, kubeadmin password

### 5. Register contexts and provision automation SAs

Run for each cluster after provisioning:

```bash
bash examples/scripts/cluster-onboarding/01_register_cluster.sh
bash examples/scripts/cluster-onboarding/02_provision_automation_sa.sh
```

Then build the Spoke fleet kubeconfig:

```bash
bash examples/scripts/cluster-onboarding/03_build_spoke_fleet.sh --auto
```

### 6. Continue with the collection

You are now ready to run the collection playbooks. See [getting-started.md](../../../../docs/onboarding/getting-started.md)
starting from Step 1.

> **Note:** The path to this README from the project root is
> **`examples/terraform/azure/aro-lab-hub/README.md`**. The **`cp`** commands in step 2
> use paths relative to the project root.

---

## Terraform workspace layout

The wrapper script creates one Terraform workspace per cluster inside the **`terraform-aro`**
project directory. Each workspace has its own independent state, so provisioning or
destroying one cluster does not affect the others.

To list all workspaces:

```bash
cd ~/Documents/RedHat/LAB/TERRAFORM/terraform-aro
terraform workspace list
```

To destroy a cluster provisioned with the wrapper:

```bash
bash .local/azure/provision-aro-terraform.sh --cluster acmdr-lab-hub-01 --apply --destroy
```

---

## Notes

- OCP version **`4.20.15`** is pinned in all templates. To use a different version, change
  **`aro_version`** in the tfvars file. Check available versions with:
  **`az aro get-versions --location eastus --output table`**
- VNet CIDRs use **`/20`** (4096 addresses) to leave room for optional jumphost and firewall
  subnets. The collection itself only uses the control and machine subnets.
- The **`enable_managed_identities = false`** default in **`terraform-aro`** means ARO uses a
  Service Principal. The wrapper sets **`ARM_USE_AZURE_CLI=true`** so Terraform authenticates
  via the current **`az`** session (required for SP creation).
