###############################################################################
# Dev environment - hub-and-spoke Azure stack in UAE North.
#
# Topology:
#   - Hub VNet  (rg-<prefix>-hub)        : shared services + central Private DNS
#   - Spoke VNet (rg-<prefix>-spoke)     : workload network (AKS, App Svc, PEs)
#   - Workloads (rg-<prefix>-platform)   : AKS, ACR, Key Vault, App Service,
#                                          Storage - ALL attached to the spoke
###############################################################################

locals {
  suffix = random_string.suffix.result

  # Globally unique resource names
  acr_name     = lower(replace("${var.name_prefix}acr${local.suffix}", "-", ""))
  kv_name      = lower(substr("kv-${var.name_prefix}-${local.suffix}", 0, 24))
  storage_name = lower(substr(replace("st${var.name_prefix}${local.suffix}", "-", ""), 0, 24))
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
  numeric = true
}

###############################################################################
# Resource groups
###############################################################################
resource "azurerm_resource_group" "core" {
  name     = "rg-${var.name_prefix}-core"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-${var.name_prefix}-hub"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "spoke" {
  name     = "rg-${var.name_prefix}-spoke"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-${var.name_prefix}-platform"
  location = var.location
  tags     = var.tags
}

###############################################################################
# Log Analytics workspace (shared)
###############################################################################
resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${var.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.core.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = var.tags
}

resource "azurerm_log_analytics_solution" "containers" {
  solution_name         = "ContainerInsights"
  location              = var.location
  resource_group_name   = azurerm_resource_group.core.name
  workspace_resource_id = azurerm_log_analytics_workspace.this.id
  workspace_name        = azurerm_log_analytics_workspace.this.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }
}

###############################################################################
# Hub network (VNet + central Private DNS zones)
###############################################################################
module "hub_network" {
  source              = "../../modules/hub_network"
  name_prefix         = var.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  vnet_address_space  = var.hub_vnet_address_space
  tags                = var.tags
}

###############################################################################
# Spoke network (workload VNet, peered with hub, DNS-linked)
###############################################################################
module "spoke_network" {
  source                     = "../../modules/spoke_network"
  name_prefix                = var.name_prefix
  spoke_name                 = "workload"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.spoke.name
  vnet_address_space         = var.spoke_vnet_address_space
  hub_vnet_id                = module.hub_network.vnet_id
  hub_vnet_name              = module.hub_network.vnet_name
  hub_resource_group_name    = module.hub_network.resource_group_name
  hub_private_dns_zone_names = module.hub_network.private_dns_zone_names
  tags                       = var.tags
}

###############################################################################
# AKS - in the spoke
###############################################################################
module "aks" {
  source                     = "../../modules/aks"
  cluster_name               = "aks-${var.name_prefix}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.platform.name
  aks_subnet_id              = module.spoke_network.aks_subnet_id
  tenant_id                  = var.tenant_id
  admin_group_object_ids     = var.aks_admin_group_object_ids
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = var.tags
}

###############################################################################
# ACR - private endpoint in the spoke (with AKS pull permission)
###############################################################################
module "acr" {
  source                     = "../../modules/acr"
  name                       = local.acr_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.platform.name
  private_endpoint_subnet_id = module.spoke_network.pe_subnet_id
  private_dns_zone_id        = module.hub_network.private_dns_zone_ids["acr"]
  geo_replication_locations  = var.acr_geo_replication_locations
  aks_kubelet_object_id      = module.aks.kubelet_object_id
  tags                       = var.tags
}

###############################################################################
# Key Vault - private endpoint in the spoke
###############################################################################
module "keyvault" {
  source                     = "../../modules/keyvault"
  name                       = local.kv_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.platform.name
  private_endpoint_subnet_id = module.spoke_network.pe_subnet_id
  private_dns_zone_id        = module.hub_network.private_dns_zone_ids["keyvault"]
  kv_admin_principal_ids     = var.kv_admin_principal_ids
  # Map keys are static (known at plan); values can be computed/unknown.
  # Staging slot is always created (app_service var.create_staging_slot defaults to true).
  kv_secret_user_principal_ids = {
    aks                = module.aks.kv_secrets_provider_object_id
    appservice         = module.appservice.principal_id
    appservice_staging = module.appservice.staging_principal_id
  }
  tags = var.tags
}

###############################################################################
# App Service (.NET) - VNet-integrated into the spoke
###############################################################################
module "appservice" {
  source                     = "../../modules/app_service"
  app_name                   = var.appsvc_app_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.platform.name
  appsvc_subnet_id           = module.spoke_network.appsvc_subnet_id
  plan_sku                   = var.appsvc_plan_sku
  zone_redundant             = var.appsvc_zone_redundant
  worker_count               = var.appsvc_worker_count
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  app_settings = {
    "KEYVAULT_URI"    = module.keyvault.vault_uri
    "STORAGE_ACCOUNT" = module.storage.name
    "BLOB_ENDPOINT"   = module.storage.primary_blob_endpoint
  }
  tags = var.tags
}

###############################################################################
# Storage account - private endpoints in the spoke
###############################################################################
module "storage" {
  source                     = "../../modules/storage"
  name                       = local.storage_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.platform.name
  private_endpoint_subnet_id = module.spoke_network.pe_subnet_id
  private_dns_zone_ids       = module.hub_network.private_dns_zone_ids
  enable_blob_endpoint       = true
  enable_file_endpoint       = var.storage_enable_file_endpoint
  enable_queue_endpoint      = var.storage_enable_queue_endpoint
  enable_table_endpoint      = var.storage_enable_table_endpoint
  enable_dfs_endpoint        = var.storage_enable_dfs_endpoint
  # Map keys are static (known at plan); values can be computed/unknown.
  # Staging slot is always created.
  blob_data_contributor_principal_ids = {
    appservice         = module.appservice.principal_id
    appservice_staging = module.appservice.staging_principal_id
  }
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = var.tags
}

###############################################################################
# Action group + a couple of representative alerts (CPU, 5xx)
###############################################################################
resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-${var.name_prefix}-ops"
  resource_group_name = azurerm_resource_group.core.name
  short_name          = "ops"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "aks_node_cpu" {
  name                = "alert-aks-node-cpu"
  resource_group_name = azurerm_resource_group.platform.name
  scopes              = [module.aks.id]
  description         = "AKS node CPU > 80% for 15 minutes"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}

resource "azurerm_monitor_metric_alert" "appsvc_5xx" {
  name                = "alert-appsvc-http5xx"
  resource_group_name = azurerm_resource_group.platform.name
  scopes              = [module.appservice.id]
  description         = "App Service HTTP 5xx > 10 in 5 minutes"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}
