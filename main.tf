locals {
  # provisioningScriptEntryPoint is the *container* name; MDP always runs Setup.sh (Linux) / Setup.ps1 (Windows) from it.
  script_container_name = "provisioningscript"
  log_container_name    = "mdpprovisioningscriptlogs"
  script_content        = replace(file("${path.module}\\scripts\\Setup.sh"), "\r\n", "\n")
}

resource "azurerm_resource_group" "pool" {
  name     = "${var.name_prefix}-rg"
  location = var.location
}

resource "azurerm_dev_center" "pool" {
  name                = "${var.name_prefix}-dc"
  location            = azurerm_resource_group.pool.location
  resource_group_name = azurerm_resource_group.pool.name
}

resource "azurerm_dev_center_project" "pool" {
  name                = "${var.name_prefix}-project"
  location            = azurerm_resource_group.pool.location
  resource_group_name = azurerm_resource_group.pool.name
  dev_center_id       = azurerm_dev_center.pool.id
}

resource "azurerm_user_assigned_identity" "pool" {
  name                = "${var.name_prefix}-identity"
  location            = azurerm_resource_group.pool.location
  resource_group_name = azurerm_resource_group.pool.name
}

resource "azurerm_storage_account" "provisioning" {
  name                            = var.storage_account_name
  location                        = azurerm_resource_group.pool.location
  resource_group_name             = azurerm_resource_group.pool.name
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  public_network_access           = "Enabled"
}

resource "azurerm_storage_container" "scripts" {
  name                  = local.script_container_name
  storage_account_id    = azurerm_storage_account.provisioning.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "logs" {
  name                  = local.log_container_name
  storage_account_id    = azurerm_storage_account.provisioning.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "setup" {
  name                 = "Setup.sh"
  storage_container_id = azurerm_storage_container.scripts.id
  type                 = "Block"
  content_type         = "text/x-shellscript"
  source_content       = local.script_content
  content_md5          = md5(local.script_content)
}

resource "azurerm_role_assignment" "script_reader" {
  scope                = azurerm_storage_container.scripts.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.pool.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "log_writer" {
  scope                = azurerm_storage_container.logs.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.pool.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azapi_resource" "pool" {
  type      = "Microsoft.DevOpsInfrastructure/pools@2026-06-02"
  name      = var.pool_name
  parent_id = azurerm_resource_group.pool.id
  location  = azurerm_resource_group.pool.location

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.pool.id]
  }

  body = {
    properties = {
      devCenterProjectResourceId = azurerm_dev_center_project.pool.id
      maximumConcurrency         = var.maximum_concurrency
      agentProfile = {
        kind = "Stateless"
      }
      organizationProfile = {
        kind = "AzureDevOps"
        organizations = [{
          url         = var.azure_devops_organization_url
          projects    = var.azure_devops_projects
          parallelism = var.maximum_concurrency
          openAccess  = false
        }]
        permissionProfile = {
          kind = "CreatorOnly"
        }
      }
      fabricProfile = {
        kind = "Vmss"
        sku = {
          name = var.vm_size
        }
        images = [{
          wellKnownImageName                         = "ubuntu-24.04-g2"
          aliases                                    = ["ubuntu-24.04-g2"]
          buffer                                     = "*"
          provisioningScriptStorageAccountResourceId = azurerm_storage_account.provisioning.id
          provisioningScriptEntryPoint               = azurerm_storage_container.scripts.name
          provisioningScriptManagedIdentityClientId  = azurerm_user_assigned_identity.pool.client_id
          provisioningScriptShouldRestart            = var.restart_after_provisioning
        }]
      }
    }
  }

  depends_on = [
    azurerm_storage_blob.setup,
    azurerm_role_assignment.script_reader,
    azurerm_role_assignment.log_writer,
  ]
}
