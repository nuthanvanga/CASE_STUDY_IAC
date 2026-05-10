# Architecture & design notes

## Topology (UAE North) — hub & spoke

The platform is split across four resource groups in a single subscription. The
network is a classic Azure **hub-and-spoke**: a hub VNet hosts shared services
and the central Private DNS zones; a spoke VNet hosts every workload and is
bidirectionally peered with the hub. New spokes (non-prod, DR, partner) plug
into the same hub without re-IP'ing.

```
                                        Subscription (prod)
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │  rg-<prefix>-core                                                           │
 │   ├── Log Analytics workspace (90 d) + Container Insights                   │
 │   └── Action group + metric alerts                                          │
 │                                                                             │
 │  rg-<prefix>-hub                       rg-<prefix>-spoke                    │
 │   Hub VNet  10.10.0.0/16    ◄──peer──► Spoke VNet  10.20.0.0/16             │
 │   ├── GatewaySubnet         (reserved) ├── snet-aks       10.20.0.0/22 ──► AKS
 │   ├── AzureBastionSubnet    (reserved) ├── snet-appsvc    10.20.4.0/24 ──► AppSvc VNet integ.
 │   ├── AzureFirewallSubnet   (reserved) ├── snet-pe        10.20.5.0/24 ──► Private Endpoints (KV / ACR / Storage / AppSvc)
 │   ├── snet-shared           10.10.3/24 └── snet-appgw     10.20.6.0/24 ──► AppGW WAF v2
 │   └── Private DNS zones (linked to       NAT Gateway (zone-redundant)       │
 │       BOTH hub and spoke):               NSGs on AKS + PE subnets           │
 │       privatelink.vaultcore.azure.net                                       │
 │       privatelink.azurecr.io                                                │
 │       privatelink.blob/file/queue/table/dfs.core.windows.net                │
 │       privatelink.azurewebsites.net (+ scm)                                 │
 │                                                                             │
 │  rg-<prefix>-platform   (workload PaaS — all attached to the spoke)         │
 │   ├── AKS         (private cluster, 3 zones, snet-aks)                      │
 │   ├── ACR         (Premium, geo-replicated, PE in snet-pe)                  │
 │   ├── Key Vault   (Premium, RBAC, PE in snet-pe)                            │
 │   ├── Storage     (StorageV2, ZRS, AAD-only, PE in snet-pe)                 │
 │   └── App Service (PremiumV3, ZR, slot, VNet-integrated into snet-appsvc)   │
 │                                                                             │
 │  Internet ──► AppGW WAF v2 (snet-appgw) ──► AKS Ingress / App Service       │
 └─────────────────────────────────────────────────────────────────────────────┘
```

### Why hub-and-spoke?

- **Centralised egress / shared services.** A future Azure Firewall, ExpressRoute / VPN gateway, or DNS-private-resolver lives in the hub and is reused by every spoke.
- **Single source of truth for Private DNS.** Each `privatelink.*` zone is created **once** in the hub and linked to every spoke VNet. No drifted zones, no duplicated records.
- **Blast-radius isolation.** Workloads (AKS / App Service / KV / Storage) live in spoke subnets that are independently NSG'd. New environments (dev, dr, partner) become new spokes without touching the hub.
- **No transitive peering.** Spoke ↔ spoke goes via a hub NVA / firewall, which is the recommended Azure pattern. The peering on the hub side has `allow_gateway_transit` ready, the spoke side has `allow_forwarded_traffic` enabled.

## High availability

| Layer            | Decision                                                                 |
|------------------|--------------------------------------------------------------------------|
| AKS              | Standard SKU (uptime SLA), 3-zone node pools, max-surge 33%, PDB ≥2     |
| App Service      | PremiumV3 plan with `zone_balancing_enabled = true`, ≥3 instances, slot |
| Disks (PVC)      | Premium ZRS managed disks                                                |
| ACR              | Premium with `zone_redundancy_enabled = true` + secondary region geo-rep|
| Networking       | NAT Gateway zone-redundant, Standard Public IP zone-redundant           |
| Storage backend  | Terraform state in GRS storage account                                  |

## Security

- **Identity:** SP-less CI/CD via OIDC Workload Identity Federation; pods authenticate with **AKS Workload Identity** federated to a UAMI; App Service uses System-assigned Managed Identity; Storage account is **AAD-only** (`shared_access_key_enabled = false`).
- **Secrets:** centralised in **Key Vault Premium** (HSM, purge protection). Access via **RBAC** only. Pods read secrets via the **CSI Secrets Store** addon with auto-rotation. Public network access disabled on KV; access is via private endpoint.
- **Network:** private AKS API server, private endpoints for KV / ACR / Storage in the spoke `snet-pe` subnet, NSGs on AKS and PE subnets, Cilium **NetworkPolicy** in the cluster, and an outbound NAT Gateway for stable public IPs.
- **Posture & runtime:** Microsoft Defender for **Cloud (CSPM)**, **Containers**, **App Service**, **Key Vault**, **Storage**. Azure Policy add-on enforces guardrails.
- **TLS:** App Service requires TLS 1.2+, FTPS disabled, HTTPS-only. Storage requires TLS 1.2+. Ingress uses cert-manager + HSTS.
- **Pod security:** PSA `restricted` on the namespace, non-root containers, readonly root FS, dropped capabilities, seccomp `RuntimeDefault`.
- **Code quality / SAST:** **SonarQube** prepare → analyze → publish runs in the .NET pipeline (MSBuild scanner mode). The `SonarQubePublish` step waits for the project's quality gate and fails the build if it doesn't pass.

## Networking best practices applied

- **Hub-and-spoke** with bidirectional VNet peering; non-overlapping CIDRs (`10.10.0.0/16` hub, `10.20.0.0/16` spoke).
- **Central Private DNS zones** in the hub RG, linked to both hub and spoke — every private endpoint resolves to the same private IP from anywhere in the topology.
- Separate **subnets** per workload type in the spoke (AKS, App Service delegation, Private Endpoints, App Gateway).
- **Service endpoints** on AKS subnet for KV/ACR/Storage in addition to private DNS — avoids unnecessary egress through NAT.
- **Outbound type `userAssignedNATGateway`** for predictable egress IPs, instead of relying on Standard Load Balancer SNAT (which is rate-limited).
- Reserved hub subnets (`GatewaySubnet`, `AzureBastionSubnet`, `AzureFirewallSubnet`) so VPN/ExpressRoute, Bastion or Azure Firewall can be added later without re-cidr'ing.

## Observability

- **Log Analytics workspace** (90-day retention, 50 GB daily quota) is the single sink.
- **Container Insights** + AKS diagnostic logs (kube-apiserver, audit, scheduler, controller, autoscaler, guard).
- **Application Insights** auto-instruments App Service, ships to the same workspace.
- **Diagnostic Settings** on every PaaS resource (App Service, AKS, KV, ACR).
- **Azure Monitor metric alerts** wired to an action group with email receivers (extend to Teams / PagerDuty as needed).
- The HPA scrapes a **Pods** metric (`http_requests_per_second`) — provided by `kube-prometheus-stack` + `prometheus-adapter`, or the Azure Monitor managed Prometheus + custom-metrics adapter.

## CI/CD model

| Pipeline | What it does | Approvals |
|----------|--------------|-----------|
| `azure-pipelines-terraform.yml` | fmt / validate / tflint / tfsec / checkov → plan (artifact) → apply | environment `prod-infra` requires reviewers |
| `azure-pipelines-dotnet-app.yml` | restore / **SonarQube prepare** / build / test / **analyze + publish quality gate** / publish → deploy to staging slot → smoke test → swap | environment `prod-app` requires reviewers |

Both rely on a single Azure service connection (`azurerm-prod-oidc`) configured with Workload Identity Federation, so no service-principal secrets sit in Azure DevOps. The .NET pipeline additionally needs a **SonarQube** service connection (default name `sonarqube-prod`) provided by the SonarQube Azure DevOps extension.

## Production hardening checklist

- [ ] Terraform state encrypted at rest (Azure Storage default, plus KV-owned key for CMK if required).
- [ ] State storage account locked to private endpoint and AAD auth only.
- [ ] AKS local accounts disabled, AAD auth required.
- [ ] All resources tagged `environment, owner, cost_center, managed_by`.
- [ ] Cost Management budget + alerts attached to the subscription / resource groups.
- [ ] DR plan documented (geo-replicated ACR + LAW; AKS cluster recreated from Terraform; PVC snapshots restored).
