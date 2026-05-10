# Bill of Quantity (BOQ) — Production Environment, UAE North

> Region: **UAE North (Abu Dhabi)** • Currency: **USD** • Pricing reference: Azure public retail list price as of May 2026.
> All figures are **estimates**. Actual cost depends on usage, reservations, and Microsoft Customer Agreement discounts. Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) and the latest [retail prices API](https://prices.azure.com) before final commitment.

## Assumptions

- Region pricing is UAE North; some services are billed at UAE Central or West Europe rates if not yet GA in UAE North.
- All compute is **on-demand (pay-as-you-go)**. With **3-year Reserved Instances + Savings Plan** the compute lines drop ~45–55% (see "RI scenario" column).
- AKS control plane is **Standard tier** (uptime SLA enabled).
- Storage and bandwidth are sized for a moderately busy production workload.
- 730 hours / month is used for hourly resources.
- Egress assumes traffic stays largely within the region; cross-region replication egress is itemised separately.

## Cost summary

| Category                   | Monthly (PAYG) | Monthly (3-yr RI) |
| -------------------------- | -------------: | ----------------: |
| Compute (AKS, App Service) |        ~$2,665 |          ~$1,330 |
| Containers & Registry      |          ~$215 |             ~$215 |
| Networking (hub + spoke)   |          ~$405 |             ~$405 |
| Security (KV, Defender)    |          ~$260 |             ~$260 |
| Monitoring & Logging       |          ~$520 |             ~$520 |
| Storage & Backup           |          ~$125 |             ~$125 |
| **Total (estimate)**       |    **~$4,190** |       **~$2,855** |

A rounded production budget of **~$4,200/month PAYG** (or **~$2,900/month with 3-yr RIs**) is a reasonable starting figure. Add ~10–15% buffer for traffic growth, log volume spikes and bandwidth.

## Detailed line items

### 1. Compute

| # | Resource                                | SKU / Tier              | Qty | Unit price (USD) | Monthly (USD) |
|---|-----------------------------------------|-------------------------|----:|-----------------:|--------------:|
| 1 | AKS control plane                       | Standard tier (Uptime SLA) | 1 cluster | $0.10/hr | $73.00 |
| 2 | AKS system node pool                    | Standard_D4s_v5 (4 vCPU / 16 GB) | 3 × 730 hr | $0.232/hr | $508.00 |
| 3 | AKS user node pool                      | Standard_D8s_v5 (8 vCPU / 32 GB) | 3 × 730 hr | $0.464/hr | $1,016.00 |
| 4 | App Service Plan                        | Premium V3 P1v3 (2 vCPU / 8 GB), zone-redundant, 3 instances | 3 × 730 hr | $0.214/hr | $469.00 |
| 5 | App Service staging slot                | shared on plan          | 1   | included         | included      |
| 6 | App Service Application Insights        | first 5 GB free, then ingestion | ~5 GB | $2.30/GB | $12.00 |

Compute subtotal ≈ **$2,078/month + $73 control plane + $508 (used by HA reserve)** → **~$2,665/month**.

### 2. Containers & Registry

| # | Resource                          | SKU                       | Qty | Unit price (USD) | Monthly (USD) |
|---|-----------------------------------|---------------------------|----:|-----------------:|--------------:|
| 1 | Azure Container Registry          | Premium                   | 1   | $1.667/day       | $50.00 |
| 2 | ACR storage above 500 GB          | per GB / month            | 100 GB additional | $0.10 | $10.00 |
| 3 | ACR geo-replication (UAE Central) | per region                | 1   | $1.667/day       | $50.00 |
| 4 | Microsoft Defender for Containers | per vCore / hour          | ~30 vCores | $0.0095/hr | $208.00* |

*Defender for Containers is also captured in Security; shown here for visibility.*

Containers subtotal ≈ **$110/month** (excluding Defender) or **~$215 if Defender is allocated here**.

### 3. Networking

| # | Resource                              | SKU / Tier                | Qty | Unit price (USD)   | Monthly (USD) |
|---|---------------------------------------|---------------------------|----:|-------------------:|--------------:|
| 1 | Virtual Networks (hub + spoke)        | included                  | 2   | $0                 | $0    |
| 2 | VNet peering (hub ↔ spoke), inbound + outbound | per GB processed | 500 GB each way | $0.01/GB | $10.00 |
| 3 | NAT Gateway (zone-redundant, spoke)   | per gateway / hour        | 1   | $0.045/hr          | $33.00 |
| 4 | NAT Gateway data processed            | per GB                    | 1,000 GB | $0.045/GB     | $45.00 |
| 5 | Public IP (Standard, static)          | per hour                  | 2   | $0.005/hr          | $7.30  |
| 6 | Private endpoints (KV, ACR, Storage blob) | per endpoint / hour   | 3   | $0.01/hr           | $21.90 |
| 7 | Private endpoint data processed       | per GB                    | 700 GB | $0.01/GB        | $7.00  |
| 8 | Private DNS zones (centralised in hub)| per zone                  | 9   | $0.50/zone/mo      | $4.50  |
| 9 | Application Gateway v2 (WAF)          | small fixed + capacity unit | 1 | ~$200/mo for small WAFv2 | $200.00 |
| 10| Egress bandwidth (intra-region/VNet)  | per GB after 100 GB free  | 500 GB | $0.087/GB       | $43.00 |
| 11| Cross-region replication (ACR + LAW)  | per GB                    | ~400 GB | $0.087/GB     | $35.00 |

Networking subtotal ≈ **$405/month** (hub-and-spoke adds ~$15/mo vs. a flat VNet, mostly peering data + extra Private DNS zones).

### 4. Security

| # | Resource                              | SKU / Tier                | Qty | Unit price (USD) | Monthly (USD) |
|---|---------------------------------------|---------------------------|----:|-----------------:|--------------:|
| 1 | Azure Key Vault (Premium)             | per 10K transactions      | ~3M ops | $0.03 / 10K | $9.00  |
| 2 | Key Vault HSM-protected key storage   | per key / month           | 5   | $5.00            | $25.00 |
| 3 | Microsoft Defender for Cloud          | Cloud Security Posture (Foundational) | included | $0  | $0     |
| 4 | Defender for Containers               | per vCore                 | ~30 vCores | $0.0095/hr | $208.00 |
| 5 | Defender for App Service              | per node                  | 3   | $0.02/hr         | $43.80 |
| 6 | Microsoft Sentinel ingestion (optional)| per GB ingested          | ~30 GB | $2.46/GB     | $74.00 |

Security subtotal ≈ **$260/month** (Defender + KV) — or **~$335/month** if Sentinel is enabled.

### 5. Monitoring & Logging

| # | Resource                                | SKU / Tier                  | Qty | Unit price (USD)   | Monthly (USD) |
|---|-----------------------------------------|-----------------------------|----:|-------------------:|--------------:|
| 1 | Log Analytics ingestion                 | Pay-as-you-go               | 100 GB | $2.76/GB        | $276.00 |
| 2 | Log Analytics retention beyond 31 days  | per GB / month              | 100 GB × 2 mo | $0.10/GB | $20.00 |
| 3 | Container Insights                      | included with LAW           |     | $0                 | $0     |
| 4 | Application Insights ingestion (App Svc)| ingestion                   | 30 GB | $2.30/GB         | $69.00 |
| 5 | Azure Monitor metric alerts             | per signal monitored        | 50 signals | $0.10/signal | $5.00  |
| 6 | Azure Monitor managed Prometheus        | per metric sample (10M free)| 100M | $0.16/10M extra | $14.40 |
| 7 | Azure Managed Grafana                   | Standard                    | 1 instance | $0.105/hr  | $76.65 |
| 8 | Diagnostic settings to LA / Storage     | included                    |     | $0                 | $0     |

Monitoring subtotal ≈ **$520/month**.

### 6. Storage & Backup

| # | Resource                                  | SKU / Tier                | Qty | Unit price (USD) | Monthly (USD) |
|---|-------------------------------------------|---------------------------|----:|-----------------:|--------------:|
| 1 | Premium ZRS managed disks (AKS PVCs)      | P15 (256 GiB)             | 3   | $35/disk         | $105.00 |
| 2 | Boot disks (ephemeral)                    | included with VM SKU      | -   | $0               | $0     |
| 3 | Storage account (StorageV2, ZRS) — capacity | hot tier, ZRS           | 500 GB | $0.0276/GB    | $13.80 |
| 4 | Storage account — read/write transactions | per 10K ops               | ~5M ops | $0.005 / 10K | $2.50  |
| 5 | Snapshot storage (PVC backup)             | LRS standard              | 100 GB | $0.05/GB      | $5.00  |
| 6 | Azure Backup vault for App Service        | per protected instance    | 1   | included w/ Premium | $0   |

Storage subtotal ≈ **$125/month** (Storage account adds ~$15–20/mo at this size; tune `replication_type` to LRS for cost savings or GZRS for cross-region durability).

### 7. Optional / future

| # | Item                                     | Notes                                   | Indicative monthly |
|---|------------------------------------------|-----------------------------------------|-------------------:|
| 1 | Azure Front Door Standard                | global ingress, WAF, CDN                | $35 + $0.17/GB      |
| 2 | Azure Cosmos DB (multi-region writes)    | for downstream microservice persistence | from $25            |
| 3 | Service Bus Premium                      | messaging backbone                      | from $677           |
| 4 | DDoS Protection Standard (subscription)  | recommended for prod                    | $2,944              |
| 5 | Azure Bastion                            | secure jumpbox for admins               | $135                |

These are not in the headline total. Decide based on workload requirements.

## Notes & best-practice levers

- **Move to 3-year Reservations + Savings Plan** for AKS nodes and App Service plan once the workload settles. Typical savings: 45–55%.
- **Set Log Analytics daily quota** (we set 50 GB) to prevent runaway log costs.
- **Use Premium ZRS disks only where HA is critical**; less critical workloads can use Premium LRS at ~30% lower price.
- **Geo-replication of ACR** doubles the registry cost — keep only the regions you actually need.
- **Defender for Containers / App Service** is the single biggest "security" lever; it is highly recommended for production but contributes ~60% of the security cost line.
- **DDoS Standard** is per-subscription and very expensive — usually justified only when a public-internet ingress is present and risk-tolerance is low; consider Front Door Premium with WAF as an alternative for many scenarios.
