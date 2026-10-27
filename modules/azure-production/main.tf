# A golden-path project's production on Azure: one resource group with a Container Apps environment, a container
# registry, a log workspace, a vault for the apps' secrets, an identity the apps run as, one Container App per deployable
# app, and optionally a migrations job. Applied by an engineer at a terminal, from a plan they read; the JettMem factory
# then releases into it as its deploy identity, and never changes what's here but each app's image, its revisions and its
# traffic, which this module leaves to it.
#
# No secret is ever in this code or its state: the database's connection string goes into the vault at a hidden prompt
# (README.md), and the apps read it as a Key Vault reference through their own identity, never as a plain setting.

locals {
  name = "${var.project}-production"
  tags = {
    "managed-by" = "jettmem-factory"
    "project"    = var.project
    "purpose"    = "production"
  }
  quickstart = "mcr.microsoft.com/k8se/quickstart:latest"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "production" {
  name     = local.name
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "production" {
  name                         = "${local.name}-logs"
  location                     = azurerm_resource_group.production.location
  resource_group_name          = azurerm_resource_group.production.name
  sku                          = "PerGB2018"
  retention_in_days            = 30
  daily_quota_gb               = 1
  local_authentication_enabled = false
  tags                         = local.tags
}

resource "azurerm_container_app_environment" "production" {
  name                = local.name
  location            = azurerm_resource_group.production.location
  resource_group_name = azurerm_resource_group.production.name
  logs_destination    = "azure-monitor"

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = local.tags
}

# Where the project's previews run: an environment of their own, so a preview's app can't
# reach production's by name. The factory makes and deletes each preview's apps here.
resource "azurerm_container_app_environment" "previews" {
  name                = "${var.project}-previews"
  location            = azurerm_resource_group.production.location
  resource_group_name = azurerm_resource_group.production.name
  logs_destination    = "azure-monitor"

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = merge(local.tags, { "purpose" = "previews" })
}

resource "azurerm_monitor_diagnostic_setting" "production_logs" {
  name                       = "logs-to-production-workspace"
  target_resource_id         = azurerm_container_app_environment.production.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.production.id

  enabled_log {
    category = "ContainerAppConsoleLogs"
  }

  enabled_log {
    category = "ContainerAppSystemLogs"
  }
}

# Images: the factory builds each release's here (`web:r12`), signed in as its deploy identity. No admin user.
resource "azurerm_container_registry" "production" {
  name                = var.registry
  location            = azurerm_resource_group.production.location
  resource_group_name = azurerm_resource_group.production.name
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

# What the apps and the migrations job run as: pulling images, and reading the vault's secrets.
resource "azurerm_user_assigned_identity" "apps" {
  name                = "${local.name}-apps"
  location            = azurerm_resource_group.production.location
  resource_group_name = azurerm_resource_group.production.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "apps_pull_images" {
  scope                = azurerm_container_registry.production.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.apps.principal_id
  principal_type       = "ServicePrincipal"
  description          = "Production's apps pull their release's image."
}

resource "azurerm_key_vault" "production" {
  name                       = "${var.project}-production-${substr(md5(azurerm_resource_group.production.id), 0, 6)}"
  location                   = azurerm_resource_group.production.location
  resource_group_name        = azurerm_resource_group.production.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  tags                       = local.tags
}

resource "azurerm_role_assignment" "apps_read_secrets" {
  scope                = azurerm_key_vault.production.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.apps.principal_id
  principal_type       = "ServicePrincipal"
  description          = "Production's apps read their own secrets."
}

resource "azurerm_container_app" "app" {
  for_each = var.apps

  name                         = "${var.project}-${each.key}"
  container_app_environment_id = azurerm_container_app_environment.production.id
  resource_group_name          = azurerm_resource_group.production.name
  workload_profile_name        = "Consumption"

  # Each release is a revision of its own, checked at its label before it takes traffic; the last ten are kept to roll
  # back to.
  revision_mode          = "Multiple"
  max_inactive_revisions = 10

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = azurerm_container_registry.production.login_server
    identity = azurerm_user_assigned_identity.apps.id
  }

  dynamic "secret" {
    for_each = var.database_secret ? [1] : []
    content {
      name                = "database-url"
      key_vault_secret_id = "${azurerm_key_vault.production.vault_uri}secrets/database-url"
      identity            = azurerm_user_assigned_identity.apps.id
    }
  }

  ingress {
    external_enabled = true
    target_port      = each.value.port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 2

    container {
      name   = each.key
      image  = local.quickstart
      cpu    = each.value.cpu
      memory = each.value.memory

      env {
        name  = "PORT"
        value = tostring(each.value.port)
      }

      dynamic "env" {
        for_each = var.database_secret ? [1] : []
        content {
          name        = "DATABASE_URL"
          secret_name = "database-url"
        }
      }
    }
  }

  tags = local.tags

  # The factory releases into it: each release's image, its revision's suffix and where the traffic goes are its.
  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
      template[0].revision_suffix,
      ingress[0].traffic_weight,
    ]
  }

  depends_on = [azurerm_role_assignment.apps_pull_images, azurerm_role_assignment.apps_read_secrets]
}

# The database's migrations, run once per release by the factory from the release's image.
resource "azurerm_container_app_job" "migrate" {
  count = var.migrations == null ? 0 : 1

  name                         = "${var.project}-migrate"
  location                     = azurerm_resource_group.production.location
  resource_group_name          = azurerm_resource_group.production.name
  container_app_environment_id = azurerm_container_app_environment.production.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = 600
  replica_retry_limit          = 0

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = azurerm_container_registry.production.login_server
    identity = azurerm_user_assigned_identity.apps.id
  }

  dynamic "secret" {
    for_each = var.database_secret ? [1] : []
    content {
      name                = "database-url"
      key_vault_secret_id = "${azurerm_key_vault.production.vault_uri}secrets/database-url"
      identity            = azurerm_user_assigned_identity.apps.id
    }
  }

  template {
    container {
      name    = "migrate"
      image   = local.quickstart
      command = var.migrations
      cpu     = 0.25
      memory  = "0.5Gi"

      dynamic "env" {
        for_each = var.database_secret ? [1] : []
        content {
          name        = "DATABASE_URL"
          secret_name = "database-url"
        }
      }
    }
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.apps_pull_images, azurerm_role_assignment.apps_read_secrets]
}
