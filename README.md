# Azure Production Platform — Case Study

End-to-end Azure platform package for a containerised .NET workload in
**UAE North**:

- Hub-and-spoke networking with private endpoints and central Private DNS
- AKS (private cluster, zone-redundant), ACR (Premium, geo-replication
  optional), Key Vault (Premium, RBAC, PE), App Service (PremiumV3, ZR,
  staging slot), Storage (StorageV2, ZRS)
- Azure DevOps pipelines for both Terraform and the .NET app
- Kubernetes manifests for an `orders-api` microservice
- Bill of Quantity (BOQ) sized for a moderate production workload

## Repository layout

```
E:\CaseStudy2\
├── README.md
├── .gitignore
├── terraform\                         # IaC (per-env folders + shared modules)
│   ├── envs\
│   │   ├── dev\                        # dev root (own state, smaller SKUs)
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── providers.tf
│   │   │   ├── backend.hcl.example
│   │   │   └── terraform.auto.tfvars.example
│   │   ├── staging\                    (same shape as dev)
│   │   └── prod\                       (same shape as dev)
│   └── modules\                        # shared, env-agnostic
│       ├── hub_network\               # VNet + central Private DNS zones
│       ├── spoke_network\             # peered spoke VNet + subnets
│       ├── aks\                       # private AKS, zone-redundant
│       ├── acr\                       # Premium ACR with PE
│       ├── keyvault\                  # Premium KV (RBAC) with PE
│       ├── app_service\               # P1v3 App Service + staging slot
│       └── storage\                   # StorageV2 (ZRS) with PEs
├── pipelines\
│   ├── azure-pipelines-terraform.yml  # validate / plan / apply
│   └── azure-pipelines-dotnet-app.yml # build / staging / swap
├── kubernetes\
│   ├── charts\
│   │   └── orders-api\               # Helm chart (recommended)
│   │       ├── Chart.yaml
│   │       ├── values.yaml             (defaults)
│   │       ├── values-dev.yaml         (env overrides)
│   │       ├── values-staging.yaml
│   │       ├── values-prod.yaml
│   │       └── templates\               (Deployment, Service, Ingress,
│   │                                     HPA, PDB, NetPol, SA, SPC,
│   │                                     StorageClass, PVC, Namespace)
│   └── (flat manifests)              # kubectl/kustomize fallback
│       ├── namespace.yaml
│       ├── storageclass.yaml
│       ├── pvc.yaml
│       ├── serviceaccount.yaml
│       ├── secretproviderclass.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── hpa.yaml
│       ├── pdb.yaml
│       ├── networkpolicy.yaml
│       └── kustomization.yaml
└── docs\
    ├── BOQ.md                         # Bill of Quantity (UAE North)
    ├── BOQ_UAE_North.xlsx
    ├── architecture.md                # design notes + diagram
    ├── deployment-guide.md            # step-by-step deploy
    └── generate_boq.py
```

## Case-study deliverables

| # | Requirement | Location |
| - | ----------- | -------- |
| 1 | Terraform modules for AKS, ACR, KV, App Service (HA, security, networking best practice) | [`terraform/modules/`](terraform/modules) — wired per env in [`terraform/envs/<env>/main.tf`](terraform/envs/prod/main.tf) |
| 2 | Azure DevOps CI/CD pipeline for Terraform | [`pipelines/azure-pipelines-terraform.yml`](pipelines/azure-pipelines-terraform.yml) |
| 3 | Azure DevOps CI/CD pipeline for .NET app → App Service | [`pipelines/azure-pipelines-dotnet-app.yml`](pipelines/azure-pipelines-dotnet-app.yml) |
| 4 | Kubernetes manifests (Deployment, Service, Ingress, HPA, StorageClass, PVC, +) — packaged as a Helm chart | [`kubernetes/charts/orders-api/`](kubernetes/charts/orders-api) (Helm) and [`kubernetes/`](kubernetes) (flat fallback) |
| 5 | Bill of Quantity (UAE North, monitoring + security included) | [`docs/BOQ.md`](docs/BOQ.md) and [`docs/BOQ_UAE_North.xlsx`](docs/BOQ_UAE_North.xlsx) |

For the architecture overview and a hands-on deployment walk-through see
[`docs/architecture.md`](docs/architecture.md) and
[`docs/deployment-guide.md`](docs/deployment-guide.md).

## How environments work

Each env (`dev`, `staging`, `prod`) is its own Terraform root under
`terraform/envs/<env>/` with its own `main.tf`, `variables.tf`,
`outputs.tf`, `providers.tf`. They all reference the shared modules at
`terraform/modules/` via `../../modules/<name>`. State for each env
lives in its own Azure storage account.

`terraform.auto.tfvars` is auto-loaded — no `-var-file` flag needed.
Env-specific defaults (CIDRs, SKUs, retention) are baked into each env's
`variables.tf`; only the must-fill values like `subscription_id` /
`tenant_id` go in `terraform.auto.tfvars`.

**Pipeline (Azure DevOps)** — the four backend coordinates
(`resource_group_name`, `storage_account_name`, `container_name`, `key`)
are pulled from a per-env bootstrap Key Vault `kv-tfstate-<env>` via the
`AzureKeyVault@2` task at init time. Nothing about the state location is
hard-coded in the pipeline YAML or in source control. The pipeline picks
the env folder via the `targetEnv` parameter at queue time. See
[`docs/deployment-guide.md` § 2](docs/deployment-guide.md) for the
one-time bootstrap commands.

**Local** — `cd` into the env folder, then either pull backend config
from KV (recommended) or use a local `backend.hcl`:

```
cd terraform/envs/prod
cp terraform.auto.tfvars.example terraform.auto.tfvars   # fill in real values

# Option A: pull backend config from KV
terraform init \
  -backend-config="resource_group_name=$(az keyvault secret show --vault-name kv-tfstate-prod --name tfstate-rg        --query value -o tsv)" \
  -backend-config="storage_account_name=$(az keyvault secret show --vault-name kv-tfstate-prod --name tfstate-sa        --query value -o tsv)" \
  -backend-config="container_name=$(az keyvault secret show --vault-name kv-tfstate-prod --name tfstate-container --query value -o tsv)" \
  -backend-config="key=$(az keyvault secret show --vault-name kv-tfstate-prod --name tfstate-key       --query value -o tsv)" \
  -backend-config="use_oidc=true" -reconfigure

# Option B: local backend.hcl
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl -reconfigure

# whole stack
terraform plan
terraform apply

# single resource
terraform apply -target=module.aks
```

### Per-env defaults

|                            | dev            | staging        | prod          |
| -------------------------- | -------------- | -------------- | ------------- |
| `name_prefix`              | `dev-uaen`     | `stg-uaen`     | `prod-uaen`   |
| Hub VNet                   | `10.30.0.0/16` | `10.50.0.0/16` | `10.10.0.0/16`|
| Spoke VNet                 | `10.40.0.0/16` | `10.60.0.0/16` | `10.20.0.0/16`|
| App Service plan SKU       | `B1`           | `S1`           | `P1v3`        |
| App Service workers        | 1              | 2              | 3             |
| App Service zone-redundant | no             | no             | yes           |
| Log Analytics retention    | 30 days        | 60 days        | 90 days       |
| Log Analytics quota        | 5 GB/day       | 20 GB/day      | 50 GB/day     |
| ACR geo-replication        | none           | none           | configurable  |

## High-availability, security & networking summary

**HA**
- AKS: private cluster, system + user node pools spread across 3 AZs,
  Standard tier (uptime SLA), Container Insights, automatic OS/node-image
  upgrades, maintenance window, node-pool autoscaling.
- App Service: Premium V3 with `zone_redundant = true`, 3 instances + a
  staging slot for blue/green.
- Storage / disks: Storage account uses ZRS; AKS PVCs use a custom
  `Premium_ZRS` `StorageClass` with `WaitForFirstConsumer` binding.
- Hub-and-spoke peering with NAT Gateway and central Private DNS so
  additional spokes (DR / partner) plug in without re-IPing.

**Security**
- All PaaS services (KV, ACR, Storage, App Service SCM) reachable only via
  **private endpoints** in `snet-pe`; public network access disabled.
- AKS uses **AAD integration + Azure RBAC**, **Workload Identity**, the
  **Secrets Store CSI driver** for KV mounting (no secrets in env vars),
  and the **Key Vault Provider** addon.
- Key Vault is **Premium**, **RBAC mode**, **purge protection on**.
- ACR is **Premium** with **AcrPull** granted only to the AKS kubelet
  identity; Defender for Containers can be enabled per-subscription.
- App Service uses **system-assigned managed identity** and pulls config
  from Key Vault via `@Microsoft.KeyVault(...)` references.
- Pipelines authenticate with **Workload Identity Federation (OIDC)** —
  no long-lived secrets in Azure DevOps.
- Kubernetes namespace enforces **Pod Security Standards: restricted**;
  pods run non-root with read-only root FS and dropped capabilities;
  `NetworkPolicy` restricts ingress to nginx and egress to DNS + 443.

**Networking**
- Hub VNet hosts the central **Private DNS zones** (KV, ACR, Storage,
  AppSvc); both hub and spoke are linked.
- Spoke subnets: `snet-aks`, `snet-appsvc` (delegated), `snet-pe`,
  `snet-appgw` — sized with growth headroom.
- AKS uses Azure CNI Overlay + Cilium dataplane; egress through a
  zone-redundant **NAT Gateway**.
- App Gateway WAF v2 (BOQ line item) sits in `snet-appgw` for north-south
  ingress with WAF rules.

## Quick start

1. **Bootstrap state storage** for the env you want
   (see [`docs/deployment-guide.md`](docs/deployment-guide.md) § 2).
2. **Create the OIDC service connection** `azurerm-<env>-oidc` in Azure
   DevOps (§ 3).
3. **Fill in tfvars + backend.hcl** for the env:
   ```
   cp terraform/envs/prod.tfvars.example      terraform/envs/prod.tfvars
   cp terraform/envs/prod.backend.hcl.example terraform/envs/prod.backend.hcl
   ```
4. **Run the Terraform pipeline** with `targetEnv = prod`.
5. **Federate a UAMI** to the K8s ServiceAccount (§ 5).
6. **Deploy `orders-api` with Helm** — pass UAMI client id, KV name,
   tenant id, ACR repo + tag via `--set`:
   ```
   helm upgrade --install orders-api kubernetes/charts/orders-api \
     --namespace orders --create-namespace \
     -f kubernetes/charts/orders-api/values-prod.yaml \
     --set serviceAccount.azureWorkloadIdentityClientId=$UAMI_CLIENT_ID \
     --set keyVault.name=$KV_NAME \
     --set keyVault.tenantId=$TENANT_ID \
     --set image.repository=$ACR_LOGIN_SERVER/orders-api \
     --set image.tag=$IMAGE_TAG \
     --atomic --wait --timeout 5m
   ```
7. **Run the .NET pipeline** with `targetEnv = prod` to deploy the API to
   App Service via staging slot + swap.

## Note on demonstrating against a live subscription

Per the case-study brief: an Azure test subscription was not used for a
live deployment. All Terraform, Kubernetes, and Azure DevOps YAML files
in this repo are prepared and ready for review.
