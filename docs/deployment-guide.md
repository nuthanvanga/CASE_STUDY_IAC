# Deployment guide

End-to-end walk-through to take this repo from a clean Azure subscription to
a running platform with the .NET app on App Service and the `orders-api`
microservice on AKS.

The same pipelines deploy any environment (`dev`, `staging`, `prod`) — pick
one at queue time. This guide shows commands for `prod`; substitute the env
name everywhere it appears.

## 1. Prerequisites

- Azure subscription with **Owner** role (only for the bootstrap step).
- Azure DevOps organisation + project.
- Local tools (or build agent): `terraform >= 1.5`, `azure-cli`, `kubectl`,
  `kustomize`, `helm`.
- An AAD security group for cluster admins; capture its **object id**.

## 2. Bootstrap the Terraform state backend (per env)

This is a one-time, manual step **per environment**. It creates two things:

1. **State storage** — resource group, storage account, blob container that
   holds the remote state.
2. **Bootstrap Key Vault** — holds the four backend coordinates
   (`tfstate-rg`, `tfstate-sa`, `tfstate-container`, `tfstate-key`) so the
   pipeline can pull them at `terraform init` time. Nothing about the
   state location ends up hard-coded in the pipeline YAML or in source
   control.

> Why a separate KV here? It avoids a chicken-and-egg with the workload
> Key Vault that Terraform itself creates. The bootstrap KV is owned by
> platform/ops and only stores backend bootstrapping values — one per env.

```bash
ENV=prod                          # or dev / staging
LOC=uaenorth
RG=rg-tfstate-$ENV
SA=sttfstate${ENV}uaen           # must be globally unique, lowercase, <=24 chars
CT=tfstate
KV=kv-tfstate-$ENV               # matches BACKEND_KV_NAME in the pipeline
STATE_KEY=${ENV}-uaen.tfstate

# 2.1 - State storage
az group create -n $RG -l $LOC
az storage account create -n $SA -g $RG -l $LOC \
  --sku Standard_GRS --kind StorageV2 \
  --allow-blob-public-access false --min-tls-version TLS1_2
az storage container create --account-name $SA -n $CT --auth-mode login

# 2.2 - Bootstrap Key Vault (RBAC mode, purge protection on)
az keyvault create -n $KV -g $RG -l $LOC \
  --sku standard \
  --enable-rbac-authorization true \
  --enable-purge-protection true

# 2.3 - Grant YOURSELF "Key Vault Secrets Officer" so you can write the secrets
ME_OBJID=$(az ad signed-in-user show --query id -o tsv)
KV_ID=$(az keyvault show -n $KV -g $RG --query id -o tsv)
az role assignment create \
  --assignee-object-id "$ME_OBJID" --assignee-principal-type User \
  --role "Key Vault Secrets Officer" --scope "$KV_ID"

# 2.4 - Store the backend coordinates as secrets (names match the pipeline)
az keyvault secret set --vault-name $KV --name tfstate-rg        --value "$RG"
az keyvault secret set --vault-name $KV --name tfstate-sa        --value "$SA"
az keyvault secret set --vault-name $KV --name tfstate-container --value "$CT"
az keyvault secret set --vault-name $KV --name tfstate-key       --value "$STATE_KEY"
```

### 2.5 Grant the pipeline service principal read access on the bootstrap KV

The Terraform pipeline authenticates with the OIDC service connection
`azurerm-<env>-oidc`. Its underlying app registration needs
**`Key Vault Secrets User`** on the bootstrap vault so the
`AzureKeyVault@2` task can read the four secrets.

```bash
# Object id of the SP behind the Azure DevOps service connection.
# (Find it under: App registrations -> Enterprise application -> Object ID.)
SP_OBJID="<service-principal-object-id-of-azurerm-${ENV}-oidc>"

az role assignment create \
  --assignee-object-id "$SP_OBJID" --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" --scope "$KV_ID"

# Verify
az role assignment list --scope "$KV_ID" --assignee "$SP_OBJID" -o table
# Should show one entry: "Key Vault Secrets User"
```

> If you ever rotate the state storage account, just re-run the four
> `az keyvault secret set` commands and the pipeline picks up the new
> values on its next run — no YAML edit required.

> **Local development** can either use the same KV (with
> `terraform init -backend-config="resource_group_name=$(az keyvault secret show ...)"` etc.)
> or fall back to a local `terraform/envs/<env>.backend.hcl` file
> (templates in `terraform/envs/*.backend.hcl.example`). The pipeline
> itself never reads those local files.

## 3. Configure Workload Identity Federation for Azure DevOps (per env)

Each env gets its own service connection so blast radius is limited.

1. Azure DevOps → Project Settings → **Service connections** → New →
   **Azure Resource Manager** → **Workload Identity federation (automatic)**.
2. Name it `azurerm-<env>-oidc` (e.g. `azurerm-prod-oidc`). Scope to the
   target subscription.
3. Grant the auto-created service principal **Contributor** on the
   subscription (or on the resource groups Terraform manages) and
   **Storage Blob Data Contributor** on the state storage account from § 2.
4. Note the SP's **object id** — pass it to Terraform via
   `kv_admin_principal_ids` in the env's tfvars so it can read/write
   secrets through the workload Key Vault.

## 3a. Configure SonarQube for the .NET pipeline (optional)

The .NET pipeline runs `SonarQubePrepare` / `Analyze` / `Publish`. Skip if
you don't want quality-gate enforcement.

1. Install the **SonarQube** extension for Azure DevOps from the Marketplace.
2. Project Settings → **Service connections** → New → **SonarQube**.
   Provide URL + user token. Name it `sonarqube-<env>` (matches
   `SONARQUBE_SERVICE_CONNECTION` in the pipeline).
3. In SonarQube create a project with key `<env>-uaen-app-api`. Assign a
   **Quality Gate** to it — `SonarQubePublish` will fail the build if the
   gate isn't green.
4. To use SonarCloud instead, swap the three pipeline tasks to
   `SonarCloudPrepare/Analyze/Publish@2`.

## 4. Deploy the infrastructure

The Terraform stack creates four resource groups: `rg-<prefix>-core`,
`rg-<prefix>-hub`, `rg-<prefix>-spoke`, `rg-<prefix>-platform`. Hub and
spoke VNets must not overlap each other or any on-prem range — defaults
are in each env's tfvars (see [README.md](../README.md)).

### Option A — Pipeline (recommended)

1. Push this repo to your Azure DevOps Git or a connected GitHub repo.
2. Confirm the bootstrap state storage and OIDC service connection from
   §§ 2–3 exist for the env you're deploying.
3. Create a pipeline from `pipelines/azure-pipelines-terraform.yml`.
4. Create the Azure DevOps **environment** `<env>-infra` (e.g. `prod-infra`)
   and add reviewers/approvals.
5. Run the pipeline → at queue time, pick `targetEnv = prod`. Approve the
   Apply stage when prompted.

### Option B — Local

Two ways to feed `terraform init` the backend coordinates locally.

**B.1 — Pull from the same bootstrap Key Vault the pipeline uses** (no
local file with state-location info):

```bash
ENV=prod
KV=kv-tfstate-$ENV

cd terraform
cp envs/${ENV}.tfvars.example envs/${ENV}.tfvars     # fill in real values

terraform init \
  -backend-config="resource_group_name=$(az keyvault secret show --vault-name $KV --name tfstate-rg        --query value -o tsv)" \
  -backend-config="storage_account_name=$(az keyvault secret show --vault-name $KV --name tfstate-sa        --query value -o tsv)" \
  -backend-config="container_name=$(az keyvault secret show --vault-name $KV --name tfstate-container --query value -o tsv)" \
  -backend-config="key=$(az keyvault secret show --vault-name $KV --name tfstate-key       --query value -o tsv)" \
  -backend-config="use_oidc=true" \
  -reconfigure

terraform plan  -var-file=envs/${ENV}.tfvars
terraform apply -var-file=envs/${ENV}.tfvars
```

**B.2 — Use a local `backend.hcl`** (gitignored; convenient when working
offline, but you maintain the file yourself):

```bash
cd terraform
cp envs/prod.backend.hcl.example envs/prod.backend.hcl   # fill in real values
cp envs/prod.tfvars.example      envs/prod.tfvars        # fill in real values

terraform init  -backend-config=envs/prod.backend.hcl -reconfigure
terraform plan  -var-file=envs/prod.tfvars
terraform apply -var-file=envs/prod.tfvars
```

To deploy a single resource (e.g. just AKS):

```bash
terraform apply -var-file=envs/prod.tfvars -target=module.aks
```

Valid module addresses:
`module.hub_network`, `module.spoke_network`, `module.aks`, `module.acr`,
`module.keyvault`, `module.appservice`, `module.storage`.

## 5. Federate a UAMI to the Kubernetes ServiceAccount

```bash
ENV=prod
RG=rg-${ENV}-uaen-platform
CLUSTER=aks-${ENV}-uaen

# 1. Create the User-Assigned Managed Identity
az identity create -g $RG -n orders-api-uami
UAMI_CLIENT_ID=$(az identity show -g $RG -n orders-api-uami --query clientId -o tsv)
UAMI_PRINC_ID=$(az identity show -g $RG -n orders-api-uami --query principalId -o tsv)

# 2. Federate it to the SA in the cluster
ISSUER=$(az aks show -g $RG -n $CLUSTER --query oidcIssuerProfile.issuerUrl -o tsv)
az identity federated-credential create \
  -g $RG --identity-name orders-api-uami \
  -n orders-api-fed \
  --issuer $ISSUER \
  --subject system:serviceaccount:orders:orders-api-sa

# 3. Grant Key Vault Secrets User on the workload vault
KV_URI=$(terraform -chdir=terraform output -raw key_vault_uri)
KV_NAME=$(echo "$KV_URI" | sed 's|https://||;s|\..*||')
KV_ID=$(az keyvault show -n $KV_NAME --query id -o tsv)

az role assignment create \
  --assignee-object-id $UAMI_PRINC_ID --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" --scope $KV_ID
```

Substitute `$UAMI_CLIENT_ID` (and the KV name + tenant id) into:
- `kubernetes/serviceaccount.yaml` — annotation
- `kubernetes/secretproviderclass.yaml` — `clientID`, `keyvaultName`, `tenantId`

## 6. Deploy the microservice

```bash
az aks get-credentials -g $RG -n $CLUSTER

kubectl apply -k kubernetes/
```

Watch the rollout:

```bash
kubectl -n orders rollout status deploy/orders-api
kubectl -n orders get hpa,svc,ing,pdb,pvc
```

## 7. Deploy the .NET app to App Service

1. Create Azure DevOps environments `<env>-app-staging` and `<env>-app`
   (e.g. `prod-app-staging`, `prod-app`); add reviewers on `<env>-app`.
2. Confirm the SonarQube service connection from § 3a exists (or remove
   the Sonar tasks from the pipeline).
3. Create a pipeline from `pipelines/azure-pipelines-dotnet-app.yml`.
4. Run it → pick `targetEnv = prod` at queue time. The pipeline:
   - restores and runs `SonarQubePrepare` (MSBuild scanner mode),
   - builds and tests the project under `src/` (OpenCover + Cobertura
     coverage, TRX results),
   - runs `SonarQubeAnalyze` + `SonarQubePublish` and waits for the
     quality gate,
   - publishes a ZIP,
   - deploys to the **staging** slot,
   - smoke-tests `/health`,
   - swaps **staging → production** on approval.

## 8. Day-2 / runbooks

- **Upgrade AKS:** patch happens automatically via
  `automatic_channel_upgrade = "stable"` and
  `node_os_channel_upgrade = "NodeImage"`, scheduled by the configured
  maintenance window.
- **Rotate Key Vault secrets:** update KV; the AKS CSI addon picks up the
  new value within `secret_rotation_interval` (2 minutes).
- **Add a microservice:** copy the manifests under `kubernetes/`, change
  names/labels, add new federated credentials per § 5.
- **Scale node pool:** edit `system_max_count` / `user_max_count` in the
  env's tfvars and re-apply.
- **Switch envs locally:** re-run
  `terraform init -backend-config=envs/<env>.backend.hcl -reconfigure`.

## 9. Tear-down (test environment only)

```bash
cd terraform
terraform destroy -var-file=envs/dev.tfvars
az group delete -n rg-tfstate-dev --yes --no-wait
```

Production tear-down should always be a manual, approved process.
Resource groups are protected by
`prevent_deletion_if_contains_resources = true`, so they cannot be removed
accidentally.
