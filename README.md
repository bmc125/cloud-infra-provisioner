# cloud-infra-provisioner

A multi-cloud infrastructure automation project built with Terraform, Python, and GitHub Actions. Provisions a production-ready network, security, and compute stack on **AWS**, **GCP**, **Azure**, or **OCI** — selected at deploy time with a single variable.

Built as Portfolio Project 1 of a three-part DevOps/Platform Engineering portfolio series.

---

## What this project provisions

| Layer | AWS | GCP | Azure | OCI |
|---|---|---|---|---|
| **Network** | VPC, public/private subnets, IGW, NAT Gateway, route tables | VPC (custom mode), regional subnets, Cloud Router, Cloud NAT | VNet, subnets, NAT Gateway | VCN, public/private subnets, IGW, NAT Gateway, Service Gateway |
| **Security** | Security Groups, IAM Instance Profile, optional bastion | Firewall rules, IAP SSH, Service Account | NSG, User-Assigned Managed Identity, optional Azure Bastion | NSG, Security Lists, Dynamic Group, IAM Policy |
| **Compute** | EC2 via Launch Template, IMDSv2 enforced, encrypted EBS | Compute Engine via Instance Template, OS Login enabled | Linux VMs, encrypted managed disks | OCI Compute (A1.Flex Always Free eligible), instance principal auth |
| **Observability** | VPC Flow Logs → CloudWatch | VPC Flow Logs per subnet | Network Watcher ready | VCN Flow Logs → OCI Logging |

All resources are tagged/labeled consistently and all state is stored remotely with locking.

---

## Repository layout

```
cloud-infra-provisioner/
├── modules/
│   ├── aws/
│   │   ├── vpc/            # VPC, subnets, IGW, NAT, flow logs
│   │   ├── security/       # Security groups, IAM role + instance profile
│   │   └── compute/        # Launch Template, EC2 instances, user_data
│   ├── gcp/
│   │   ├── vpc/            # VPC network, subnets, Cloud Router + NAT
│   │   ├── security/       # Firewall rules, IAP SSH, Service Account
│   │   └── compute/        # Instance Template, Compute Engine instances
│   ├── azure/
│   │   ├── vpc/            # VNet, subnets, NAT Gateway, Network Watcher
│   │   ├── security/       # NSG + associations, Managed Identity, optional Bastion
│   │   └── compute/        # Linux VMs, NICs, cloud-init bootstrap
│   └── oci/
│       ├── vpc/            # VCN, subnets, IGW, NAT GW, Service GW, flow logs
│       ├── security/       # NSG rules, Dynamic Group, IAM Policy
│       └── compute/        # OCI Compute instances (A1.Flex / E4.Flex)
│
├── environments/
│   ├── dev/                # Dev root module — single NAT, smaller instances, bastion on
│   ├── staging/            # Staging root module — multi-AZ topology, SSM/IAP access
│   └── prod/               # Prod root module — full HA, restricted ingress, no bastion
│
├── scripts/
│   └── validate_infra.py   # Post-deploy validation script (Python, all four providers)
│
├── tests/
│   └── test_validate.py    # Unit tests for validate_infra.py (pytest, no real API calls)
│
├── .github/workflows/
│   └── terraform.yml       # CI: fmt → validate → plan on PR, plan prod on merge to main
│
├── .terraform-version      # Pins Terraform version for tfenv
└── requirements.txt        # Python dependencies (provider SDKs + pytest)
```

---

## Prerequisites

### Required for all providers
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.7  
  (or [tfenv](https://github.com/tfutils/tfenv) — reads `.terraform-version` automatically)
- Git
- Python >= 3.11
- `pip install -r requirements.txt` (or only the SDK for your target provider — see below)

### Provider-specific tooling

| Provider | CLI tool | Auth method |
|---|---|---|
| AWS | [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | `aws configure` or env vars |
| GCP | [gcloud CLI](https://cloud.google.com/sdk/docs/install) | `gcloud auth application-default login` |
| Azure | [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | `az login` or service principal env vars |
| OCI | [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) | `~/.oci/config` (set up with `oci setup config`) |

---

## Quick start

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/cloud-infra-provisioner.git
cd cloud-infra-provisioner
```

### 2. Install Terraform

```bash
# With tfenv (recommended)
tfenv install   # reads .terraform-version automatically

# Or download directly from hashicorp.com and add to PATH
terraform version  # should show >= 1.7.5
```

### 3. Bootstrap remote state (one-time setup)

Terraform stores state remotely so it is never lost and never committed to git. You must create the backend resources before running `terraform init`.

> **Why not manage the state bucket with Terraform itself?**  
> Circular dependency — the resource that stores Terraform state cannot itself be managed by Terraform. Create it once manually and never touch it again.

**AWS (S3 + DynamoDB)**
```bash
# Create state bucket (replace YOUR-ORG and region as needed)
aws s3api create-bucket \
  --bucket YOUR-ORG-tf-state-us-east-1 \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket YOUR-ORG-tf-state-us-east-1 \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

**GCP (GCS bucket)**
```bash
gsutil mb -p YOUR-GCP-PROJECT -l us-central1 gs://YOUR-ORG-tf-state
gsutil versioning set on gs://YOUR-ORG-tf-state
```

**Azure (Storage Account)**
```bash
az group create --name YOUR-ORG-tfstate-rg --location eastus
az storage account create \
  --name yourorgtfstate \
  --resource-group YOUR-ORG-tfstate-rg \
  --sku Standard_LRS \
  --min-tls-version TLS1_2
az storage container create \
  --name tfstate \
  --account-name yourorgtfstate
```

**OCI (Object Storage pre-authenticated request)**  
Create a bucket in OCI Console → Object Storage, then generate a Pre-Authenticated Request (PAR) URL with read/write access. Use the `backend "http"` block in `environments/dev/main.tf`.

### 4. Update backend configuration

In `environments/dev/main.tf` (and staging/prod), update the backend block with your actual bucket name:

```hcl
backend "s3" {
  bucket         = "YOUR-ORG-tf-state-us-east-1"   # ← change this
  key            = "cloud-infra-provisioner/dev/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "terraform-state-lock"
}
```

To use a different cloud's backend, comment out the `s3` block and uncomment the appropriate backend block. Only one backend can be active at a time.

### 5. Initialize and deploy

```bash
cd environments/dev

terraform init

# Deploy to AWS
terraform plan  -var="cloud_provider=aws"
terraform apply -var="cloud_provider=aws"

# Deploy to GCP
terraform plan  -var="cloud_provider=gcp" -var="gcp_project_id=my-project-123456"
terraform apply -var="cloud_provider=gcp" -var="gcp_project_id=my-project-123456"

# Deploy to Azure
terraform plan  -var="cloud_provider=azure" -var="azure_subscription_id=<UUID>"
terraform apply -var="cloud_provider=azure" -var="azure_subscription_id=<UUID>"

# Deploy to OCI
terraform plan  -var="cloud_provider=oci" \
  -var="oci_tenancy_id=ocid1.tenancy.oc1..aaa" \
  -var="oci_compartment_id=ocid1.compartment.oc1..aaa" \
  -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
terraform apply -var="cloud_provider=oci" ...
```

### 6. Validate the deployment

Run the post-deploy validation script to confirm the infrastructure is correctly configured:

```bash
# AWS
python scripts/validate_infra.py --provider aws --env dev

# GCP
python scripts/validate_infra.py --provider gcp --env dev --gcp-project my-project-123456

# Azure
python scripts/validate_infra.py --provider azure --env dev --subscription-id <UUID>

# OCI
python scripts/validate_infra.py --provider oci --env dev --compartment-id ocid1.compartment.oc1..aaa

# JSON output (useful for CI pipelines and automated reporting)
python scripts/validate_infra.py --provider aws --env dev --format json
```

The script auto-discovers resources by tag/label so no additional arguments are required after a fresh `terraform apply`. Pass `--vpc-id` and `--instance-ids` to target specific resources explicitly.

### 7. Destroy when done

```bash
terraform destroy -var="cloud_provider=aws"
```

> **Cost warning for OCI:** The A1.Flex shape used in dev is in the Always Free tier (1 OCPU, 6 GB RAM). Standard shapes and managed Kubernetes clusters are not free. Destroy resources immediately after testing.  
> **Cost warning for Azure Bastion:** Disabled by default in dev (`enable_bastion = false`). Enabling it costs approximately $140/month. Use the Azure CLI or Cloud Shell for access instead.

---

## Configuration reference

### Universal variables (all providers)

| Variable | Description | Default |
|---|---|---|
| `cloud_provider` | Target cloud: `aws`, `gcp`, `azure`, `oci` | **required** |
| `project` | Prefix for all resource names and tags | `infra-demo` |
| `environment` | Deployment environment | `dev` / `staging` / `prod` |
| `owner` | Tag value for resource ownership | `platform-team` |
| `my_ip_cidr` | Your public IP in CIDR for SSH/bastion rules | `10.0.0.1/32` |
| `ssh_public_key` | SSH public key content (Azure and OCI only) | `""` |

### AWS variables

| Variable | Description | Default |
|---|---|---|
| `aws_region` | AWS region | `us-east-1` |

### GCP variables

| Variable | Description | Default |
|---|---|---|
| `gcp_project_id` | GCP project ID (e.g. `my-project-123456`) | `""` |
| `gcp_region` | GCP region | `us-central1` |

### Azure variables

| Variable | Description | Default |
|---|---|---|
| `azure_subscription_id` | Azure subscription UUID | `""` |
| `azure_location` | Azure region | `eastus` |

### OCI variables

| Variable | Description | Default |
|---|---|---|
| `oci_tenancy_id` | Tenancy OCID | `""` |
| `oci_user_id` | User OCID for API key auth | `""` |
| `oci_fingerprint` | API key fingerprint | `""` |
| `oci_private_key_path` | Path to OCI API private key PEM | `~/.oci/oci_api_key.pem` |
| `oci_region` | OCI region | `us-ashburn-1` |
| `oci_compartment_id` | Compartment OCID | `""` |
| `oci_availability_domains` | List of AD names in the region | `["AD-1"]` |

---

## Environment differences

| Concern | dev | staging | prod |
|---|---|---|---|
| NAT Gateways | 1 (cost saving, AZ SPOF accepted) | 1 | 1 per AZ (full HA) |
| Instance count | 1 | 2 | 3 |
| SSH/bastion | Enabled, `my_ip_cidr` restricted | Disabled — IAP/SSM only | Disabled — IAP/SSM only |
| Ingress CIDRs | `0.0.0.0/0` | Configurable | Explicit required (no default) |
| Flow log retention | 14 days | 30 days | 90 days |
| Instance size | t3.micro / e2-micro / B1s / A1.Flex | t3.micro / e2-micro | t3.small / e2-small |
| Public SSH in security check | Warning (non-blocking) | **Hard fail** | **Hard fail** |

---

## How provider selection works

All four provider blocks are declared in every environment's `main.tf`. Each provider's module set is gated by a `count` expression derived from a local boolean:

```hcl
locals {
  is_aws   = var.cloud_provider == "aws"
  is_gcp   = var.cloud_provider == "gcp"
  is_azure = var.cloud_provider == "azure"
  is_oci   = var.cloud_provider == "oci"
}

module "aws_vpc" {
  count  = local.is_aws ? 1 : 0   # produces zero resources when not targeting AWS
  source = "../../modules/aws/vpc"
  ...
}
```

When `count = 0`, Terraform creates no resources and makes no API calls for that module. Switching clouds is a single variable change. There is no shared abstraction layer between providers — each module uses the correct native primitives for its cloud.

**Why not a universal module?**  
An OCI Dynamic Group is not the same thing as an AWS IAM Instance Profile. Abstracting them behind a common interface would mean writing code that lies about what it does. Each cloud block in the environment root module is fully explicit and readable on its own.

---

## Validation script checks

`scripts/validate_infra.py` runs after every `terraform apply` as a smoke test. Resources are auto-discovered by tag/label; no manual input required for a fresh deployment.

### AWS checks

| Check | Description |
|---|---|
| `instances_running` | All expected EC2 instances are in `running` state |
| `required_tags` | `Environment`, `Project`, `ManagedBy`, `Name` present on all instances |
| `imdsv2_enforced` | `HttpTokens = required` — IMDSv1 disabled (SSRF mitigation) |
| `ebs_encryption` | All attached EBS volumes are encrypted at rest |
| `vpc_flow_logs` | At least one active flow log exists for the VPC |
| `no_public_ssh` | No security group allows `0.0.0.0/0` on port 22 (hard fail in staging/prod) |

### GCP checks

| Check | Description |
|---|---|
| `instances_running` | All instances in `RUNNING` state |
| `required_labels` | `environment`, `project`, `managedby` labels present |
| `os_login_enabled` | `enable-oslogin=TRUE` in instance metadata |
| `no_public_ssh` | No firewall rule allows `0.0.0.0/0` on port 22 |
| `subnet_flow_logs` | Flow logs enabled on all subnets |

### Azure checks

| Check | Description |
|---|---|
| `vms_running` | All VMs in `VM running` power state |
| `required_tags` | `Environment`, `Project`, `ManagedBy` present |
| `disk_encryption` | No disks with encryption explicitly disabled |
| `no_public_ssh` | No NSG rule allows `*` / `Internet` on port 22 |

### OCI checks

| Check | Description |
|---|---|
| `instances_running` | All instances in `RUNNING` lifecycle state |
| `required_tags` | `Environment`, `Project`, `ManagedBy` freeform tags present |
| `boot_volume_encryption` | In-transit encryption enabled on boot volumes |
| `no_public_ssh` | No NSG rule allows `0.0.0.0/0` on port 22 |
| `vcn_flow_logs` | Active flow log exists for the VCN |

---

## CI/CD pipeline

The GitHub Actions workflow (`.github/workflows/terraform.yml`) runs on every pull request and push to `main`.

### Jobs

| Job | Trigger | Description |
|---|---|---|
| `validate` | All PRs and pushes | `terraform fmt` check, `terraform validate` for all three environments, Python unit tests |
| `plan-dev` | PRs to `main` | `terraform plan` for dev, posts output as a PR comment |
| `plan-prod` | Push to `main` | `terraform plan` for prod (requires GitHub Environment approval) |

### Setup

1. Set the `CLOUD_PROVIDER` repository variable in **Settings → Variables → Actions**:
   - Value: `aws`, `gcp`, `azure`, or `oci`

2. Add the appropriate secrets for your provider:

**AWS**
| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM access key (read-only plan permissions minimum) |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key |

**GCP**
| Secret | Value |
|---|---|
| `GCP_CREDENTIALS_JSON` | Service account JSON key with `Viewer` + `Terraform` roles |

**Azure**
| Secret | Value |
|---|---|
| `ARM_CLIENT_ID` | Service principal client ID |
| `ARM_CLIENT_SECRET` | Service principal client secret |
| `ARM_TENANT_ID` | Azure tenant ID |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID |

**OCI**
| Secret | Value |
|---|---|
| `OCI_PRIVATE_KEY` | PEM-encoded API private key (full file contents) |
| `OCI_TENANCY_ID` | Tenancy OCID |
| `OCI_USER_ID` | User OCID |
| `OCI_FINGERPRINT` | API key fingerprint |

3. Enable **branch protection** on `main`: require the `validate` job to pass before merging.

---

## Running tests locally

```bash
pip install pytest
python -m pytest tests/ -v

# Short traceback format
python -m pytest tests/ -v --tb=short
```

All tests use `unittest.mock` — no real cloud credentials or API calls are made. The test suite covers all four providers' check functions.

---

## Common issues and fixes

**`Error: Backend configuration changed`**  
You switched backend blocks without running `terraform init -migrate-state`. Run `terraform init -reconfigure` or `terraform init -migrate-state` to re-initialize.

**`Error: No valid credential sources found` (AWS)**  
Run `aws configure` or export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

**`Error: could not find default credentials` (GCP)**  
Run `gcloud auth application-default login`.

**`Error: Error building AzureRM Client` (Azure)**  
Run `az login`, or set `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` as environment variables.

**`Error: can not create client, bad configuration` (OCI)**  
Run `oci setup config` to create `~/.oci/config`, or verify `oci_private_key_path` points to your key file.

**`ValidationError: 0.0.0.0/0 is not allowed as a bastion SSH CIDR`**  
Set `my_ip_cidr` to your actual IP: `curl ifconfig.me` then pass `-var="my_ip_cidr=$(curl -s ifconfig.me)/32"`.

**`Error: the plan file is stale`**  
A saved plan was generated against a different state version. Re-run `terraform plan -out=tfplan` and then `terraform apply tfplan`.

---

## Security notes

- **State files contain sensitive values.** State is stored encrypted in the remote backend. It is never committed to git (enforced by `.gitignore`).
- **No credentials in code.** Provider authentication uses environment variables, CLI auth, and instance principal auth — never hardcoded keys. Sensitive variables are marked `sensitive = true` in Terraform.
- **IMDSv2 enforced (AWS).** The compute module sets `http_tokens = required` in the launch template, preventing SSRF-based credential theft via the metadata service.
- **OS Login enabled (GCP).** Instance metadata SSH keys are blocked. Access is managed through IAM.
- **No public SSH in staging/prod.** The validation script treats `0.0.0.0/0` on port 22 as a hard failure in non-dev environments. In dev it is recorded as a warning but does not block deployment.
- **Principle of least privilege.** IAM roles, service accounts, and OCI policies grant only the permissions each component actually needs.

---

## Extending this project

This project is Portfolio Project 1 of three. The next two projects build on it:

- **Project 2 — GitOps CI/CD Pipeline:** Adds a GitHub Actions pipeline that builds, tests, and deploys a Python application (a containerized REST API) to the infrastructure provisioned here.
- **Project 3 — Kubernetes Workload Operator:** Provisions a managed Kubernetes cluster (EKS/GKE/AKS/OKE), deploys the Project 2 application via Helm, and adds a Python health-check operator using the Kubernetes SDK.

To add a new cloud provider to this project, create a `modules/<provider>/vpc`, `security`, and `compute` directory following the existing pattern, then add the corresponding `count`-gated module blocks to each environment's `main.tf`.

---

## License

MIT — free to use, fork, and adapt for your own portfolio or production work. Attribution appreciated but not required.
