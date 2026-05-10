###############################################################################
# Azure App Service (Linux, .NET 8)
# - Premium V3 plan (zone-redundant) for production HA.
# - VNet integration for outbound traffic; HTTPS only; TLS 1.2+ minimum.
# - System-assigned managed identity (used to read Key Vault secrets).
# - Application Insights wired in for telemetry.
# - Diagnostic settings shipping logs to Log Analytics.
###############################################################################

resource "azurerm_service_plan" "this" {
  name                   = "${var.app_name}-plan"
  resource_group_name    = var.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.plan_sku # P1v3 / P2v3 / P3v3 for prod
  zone_balancing_enabled = var.zone_redundant
  worker_count           = var.zone_redundant ? max(var.worker_count, 3) : var.worker_count
  tags                   = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.app_name}-ai"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
  workspace_id        = var.log_analytics_workspace_id
  tags                = var.tags
}

resource "azurerm_linux_web_app" "this" {
  name                          = var.app_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = azurerm_service_plan.this.id
  https_only                    = true
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.appsvc_subnet_id
  client_affinity_enabled       = false
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 5
    use_32_bit_worker                 = false
    vnet_route_all_enabled            = true

    application_stack {
      dotnet_version = "8.0"
    }

    ip_restriction_default_action = "Deny"

    dynamic "ip_restriction" {
      for_each = var.allowed_ip_rules
      content {
        name       = ip_restriction.value.name
        ip_address = ip_restriction.value.cidr
        action     = "Allow"
        priority   = ip_restriction.value.priority
      }
    }
  }

  app_settings = merge({
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE"        = "false"
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.this.connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    "ASPNETCORE_ENVIRONMENT"                     = "Production"
    "WEBSITE_RUN_FROM_PACKAGE"                   = "1"
  }, var.app_settings)

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true
    application_logs {
      file_system_level = "Information"
    }
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }
}

###############################################################################
# Deployment slot (staging) for blue/green & swap with warm-up
###############################################################################
resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.create_staging_slot ? 1 : 0
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  https_only     = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on              = true
    minimum_tls_version    = "1.2"
    ftps_state             = "Disabled"
    health_check_path      = var.health_check_path
    vnet_route_all_enabled = true
    application_stack {
      dotnet_version = "8.0"
    }
  }

  app_settings = merge({
    "ASPNETCORE_ENVIRONMENT"                = "Staging"
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
    "WEBSITE_RUN_FROM_PACKAGE"              = "1"
  }, var.app_settings)

  virtual_network_subnet_id = var.appsvc_subnet_id
  tags                      = var.tags
}

###############################################################################
# Diagnostic settings
###############################################################################
resource "azurerm_monitor_diagnostic_setting" "appsvc" {
  count                      = var.log_analytics_workspace_id == null ? 0 : 1
  name                       = "${var.app_name}-diag"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceAppLogs" }
  enabled_log { category = "AppServiceAuditLogs" }
  enabled_log { category = "AppServiceIPSecAuditLogs" }
  enabled_log { category = "AppServicePlatformLogs" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
