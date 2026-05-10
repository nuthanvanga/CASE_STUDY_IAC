###############################################################################
# Azure Kubernetes Service (AKS)
# Production hardening:
#   - Private API server (private cluster) + private DNS
#   - Azure CNI overlay networking, Cilium dataplane, network policies
#   - Workload Identity + OIDC issuer + Azure AD RBAC + Azure RBAC for K8s
#   - Zone-redundant system & user node pools, autoscaling, surge upgrades
#   - Microsoft Defender for Containers + Azure Monitor for containers
#   - Auto-upgrade channel: stable, node OS auto-upgrade: NodeImage
###############################################################################

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.cluster_name}-uami"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                              = var.cluster_name
  location                          = var.location
  resource_group_name               = var.resource_group_name
  dns_prefix                        = var.cluster_name
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = "Standard" # uptime SLA enabled
  node_resource_group               = "${var.resource_group_name}-nodes"
  private_cluster_enabled           = true
  private_dns_zone_id               = "System"
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  role_based_access_control_enabled = true
  azure_policy_enabled              = true
  local_account_disabled            = true
  automatic_channel_upgrade         = "stable"
  node_os_channel_upgrade           = "NodeImage"
  tags                              = var.tags

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_vm_size
    vnet_subnet_id               = var.aks_subnet_id
    enable_auto_scaling          = true
    min_count                    = var.system_min_count
    max_count                    = var.system_max_count
    max_pods                     = 50
    only_critical_addons_enabled = true
    os_disk_type                 = "Ephemeral"
    os_disk_size_gb              = 128
    type                         = "VirtualMachineScaleSets"
    zones                        = ["1", "2", "3"]
    orchestrator_version         = var.kubernetes_version
    upgrade_settings {
      max_surge = "33%"
    }
    tags = var.tags
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  azure_active_directory_role_based_access_control {
    managed                = true
    admin_group_object_ids = var.admin_group_object_ids
    azure_rbac_enabled     = true
    tenant_id              = var.tenant_id
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_dataplane   = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = "userAssignedNATGateway"
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    pod_cidr            = var.pod_cidr
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  microsoft_defender {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  auto_scaler_profile {
    balance_similar_node_groups  = true
    expander                     = "least-waste"
    max_graceful_termination_sec = "600"
    scale_down_unneeded          = "10m"
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+04:00"
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
      kubernetes_version,
    ]
  }
}

###############################################################################
# Application user node pool (zone-redundant, autoscaling)
###############################################################################
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_vm_size
  vnet_subnet_id        = var.aks_subnet_id
  enable_auto_scaling   = true
  min_count             = var.user_min_count
  max_count             = var.user_max_count
  max_pods              = 100
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 128
  os_type               = "Linux"
  mode                  = "User"
  zones                 = ["1", "2", "3"]
  orchestrator_version  = var.kubernetes_version
  node_labels = {
    "workload" = "general"
  }
  upgrade_settings {
    max_surge = "33%"
  }
  tags = var.tags
}

###############################################################################
# Diagnostic settings
###############################################################################
resource "azurerm_monitor_diagnostic_setting" "aks" {
  count                      = var.log_analytics_workspace_id == null ? 0 : 1
  name                       = "${var.cluster_name}-diag"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-audit" }
  enabled_log { category = "kube-audit-admin" }
  enabled_log { category = "kube-controller-manager" }
  enabled_log { category = "kube-scheduler" }
  enabled_log { category = "cluster-autoscaler" }
  enabled_log { category = "guard" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

###############################################################################
# Grant the AKS UAMI Network Contributor on the AKS subnet so it can manage
# load balancers and route tables.
###############################################################################
resource "azurerm_role_assignment" "aks_subnet" {
  scope                = var.aks_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}
