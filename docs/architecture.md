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

## Request flow — how a request reaches AKS

The path below traces a single HTTPS request from a public client to a pod
serving the `orders-api` microservice in the `orders` namespace, then the
pod's outbound calls to Azure PaaS.

```
                                  Internet
                                     │
                ┌────────────────────▼────────────────────┐
            (1) │ Public DNS: orders.example.com →        │
                │              <AppGW Public IP>          │
                └────────────────────┬────────────────────┘
                                     │  TLS 1.2+ on 443
                                     ▼
       ┌─────────────────────────────────────────────────────┐
   (2) │ Application Gateway WAF v2  — snet-appgw            │
       │   • Standard zone-redundant Public IP               │
       │   • TLS termination (cert from Key Vault)           │
       │   • WAF (OWASP Core Rule Set)                       │
       │   • Routing rule: host / path  →  backend pool      │
       └─────────────────────────┬───────────────────────────┘
                                 │  HTTPS to NGINX Internal LB IP
                                 ▼
       ┌─────────────────────────────────────────────────────┐
   (3) │ Internal Azure Load Balancer  — snet-aks            │
       │   • k8s Service type=LoadBalancer (internal)        │
       │   • Fronts the ingress-nginx controller pods        │
       │   • Health probe: GET /healthz on the controller    │
       └─────────────────────────┬───────────────────────────┘
                                 │
                                 ▼
       ┌─────────────────────────────────────────────────────┐
   (4) │ NGINX Ingress Controller  (in AKS)                  │
       │   • Second TLS terminate (cert-manager + LetsEncrypt│
       │     issuer; cert in Secret orders-api-tls)          │
       │   • Force HTTPS + HSTS                              │
       │   • Rate limit (100 RPS), security headers          │
       │   • Host orders.example.com → Service orders-api    │
       └─────────────────────────┬───────────────────────────┘
                                 │  ClusterIP service :80 → :8080
                                 │  kube-proxy / Cilium dataplane
                                 ▼
       ┌─────────────────────────────────────────────────────┐
   (5) │ NetworkPolicy `orders-api`  (orders namespace)      │
       │   • Ingress: only from ns=ingress-nginx, TCP/8080   │
       │   • Egress:  DNS (UDP/53) + 443 (KV/ACR/Storage)    │
       │   • Everything else is denied                       │
       └─────────────────────────┬───────────────────────────┘
                                 │
                                 ▼
       ┌─────────────────────────────────────────────────────┐
   (6) │ orders-api Pod  (one of N replicas, spread on 3 AZs)│
       │   • Container :8080 (.NET 8)                        │
       │   • Non-root (uid 10001), read-only root FS,        │
       │     dropped capabilities, seccomp RuntimeDefault    │
       │   • SA `orders-api-sa` annotated with UAMI          │
       │     client id (Workload Identity)                   │
       │   • Secrets mounted via CSI Secrets Store at        │
       │     /mnt/secrets-store + projected env vars         │
       └─────────────────────────┬───────────────────────────┘
                                 │  pod outbound (when needed)
                                 ▼
       ┌─────────────────────────────────────────────────────┐
   (7) │ Private endpoints in snet-pe                        │
       │   • DNS resolves orders-kv.vault.azure.net etc.     │
       │     to the PE private IP via the central Private    │
       │     DNS zones in the hub                            │
       │   • Workload Identity → AAD token → KV / ACR /      │
       │     Storage authorise via RBAC                      │
       │   • Traffic stays inside the VNet                   │
       └─────────────────────────────────────────────────────┘

       ┌─────────────────────────────────────────────────────┐
   (8) │ Egress to Internet (only if a pod calls outbound):  │
       │   spoke subnets → NAT Gateway (zone-redundant) →    │
       │   stable public IP. No SNAT-port exhaustion.        │
       └─────────────────────────────────────────────────────┘
```

### Hop-by-hop notes

1. **Public DNS** — `orders.example.com` is an A/CNAME record on a public
   DNS zone (Azure DNS or external) pointing to the standard, zone-
   redundant Public IP attached to App Gateway. Nothing else in the
   platform has a public IP.
2. **Application Gateway WAF v2** — first checkpoint. TLS terminates here
   using a cert pulled from the workload Key Vault via a User-Assigned
   Managed Identity. WAF (OWASP CRS) inspects the request; routing rules
   match host/path and forward to the backend pool whose target is the
   internal LB IP from step 3. AppGW diagnostic logs ship to the Log
   Analytics workspace.
3. **Internal Azure Load Balancer** — created automatically when the
   `ingress-nginx` Service is provisioned with type `LoadBalancer` and
   the `service.beta.kubernetes.io/azure-load-balancer-internal: "true"`
   annotation. Its private IP lives in `snet-aks`. AppGW health probes
   pass through to NGINX `/healthz`.
4. **NGINX Ingress Controller** — second TLS termination so that cert
   rotation and per-host policies are managed declaratively inside the
   cluster (cert-manager + Let's Encrypt). Annotations from
   [`ingress.yaml`](../kubernetes/ingress.yaml) enforce HSTS,
   `X-Frame-Options`, `X-Content-Type-Options`, force-HTTPS and a
   100 RPS rate limit. Routing matches `Host: orders.example.com` and
   forwards to the `orders-api` Service.
5. **NetworkPolicy** — the `orders` namespace is locked down to default-
   deny via Pod Security Standards `restricted` plus an explicit
   `NetworkPolicy`. Ingress is allowed only from the `ingress-nginx`
   namespace on TCP/8080; egress is allowed only to kube-dns and to
   TCP/443 (Azure private endpoints). This means if AppGW ever bypassed
   the controller, the pods still wouldn't accept the connection.
6. **Pod** — one of the HPA-scaled replicas (`min/max` per env in
   [`values-prod.yaml`](../kubernetes/charts/orders-api/values-prod.yaml))
   running on a node in one of three AZs. Pod-level hardening is in
   `securityContext`; service-account-level identity is via Workload
   Identity (federated UAMI annotated on the SA). Secrets are mounted
   from KV at startup via the CSI Secrets Store driver and projected as
   env vars (e.g. `ConnectionStrings__OrdersDb`). Rotation interval is
   2 minutes — secrets refresh transparently.
7. **Pod → PaaS (Key Vault, ACR, Storage)** — when the pod calls
   `https://<vault>.vault.azure.net`, the cluster's CoreDNS forwards to
   Azure DNS, which (because of the hub Private DNS zone link) returns
   the **private** IP of the KV private endpoint in `snet-pe`. The
   traffic never leaves the VNet. Authorisation is RBAC: the UAMI
   federated to the pod's SA has `Key Vault Secrets User` on the vault.
8. **Egress to Internet** — only used when a pod genuinely needs to call
   an external service (e.g. payment provider). Spoke subnets are
   associated with a zone-redundant NAT Gateway, so the egress IP is
   stable and SNAT ports are pooled — no `kube-proxy` SNAT exhaustion
   on busy nodes.

### What's NOT on this path

- **AKS API server**: private cluster, only accessible from the spoke
  (or via an Azure Bastion in the hub). Pipelines reach it via
  Workload Identity Federation through the OIDC service connection,
  not via a hard-coded kubeconfig.
- **App Service**: a separate north-south path (AppGW → App Service via
  its private endpoint in `snet-pe`, or directly via its `*.azurewebsites.net`
  hostname when public access is enabled). The request flow above is
  AKS-only.

### Where to look when something breaks

| Symptom                          | First place to look                                     |
| -------------------------------- | ------------------------------------------------------- |
| Cert errors at the edge          | App Gateway listener / KV cert UAMI assignment           |
| 502 from AppGW                   | AppGW backend health, NGINX LB private IP, NSG on `snet-aks` |
| 502/504 from NGINX               | `kubectl -n orders get pods,endpoints,svc` and `kubectl logs` |
| 403 mounting secrets             | UAMI federated credential subject, KV RBAC role          |
| Pod can't resolve KV/ACR/Storage | Private DNS zone links to the spoke VNet                 |
| Image pull failures              | AKS kubelet identity AcrPull role on ACR                 |

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
