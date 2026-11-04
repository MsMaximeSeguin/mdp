mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id               = "00000000-0000-0000-0000-000000000000"
  storage_account_name          = "mdpprovisioningtest"
  azure_devops_organization_url = "https://dev.azure.com/example"
  azure_devops_projects         = ["Example project"]
}

override_resource {
  target = azurerm_resource_group.pool
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mdpdemo-rg"
  }
}

override_resource {
  target = azurerm_storage_account.provisioning
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mdpdemo-rg/providers/Microsoft.Storage/storageAccounts/mdpprovisioningtest"
  }
}

override_resource {
  target = azurerm_storage_container.scripts
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mdpdemo-rg/providers/Microsoft.Storage/storageAccounts/mdpprovisioningtest/blobServices/default/containers/provisioningscript"
  }
}

override_resource {
  target = azurerm_storage_container.logs
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mdpdemo-rg/providers/Microsoft.Storage/storageAccounts/mdpprovisioningtest/blobServices/default/containers/mdpprovisioningscriptlogs"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.pool
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mdpdemo-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mdpdemo-identity"
    client_id    = "11111111-1111-1111-1111-111111111111"
    principal_id = "22222222-2222-2222-2222-222222222222"
  }
}

run "provisioning_configuration" {
  command = apply

  assert {
    condition     = azapi_resource.pool.type == "Microsoft.DevOpsInfrastructure/pools@2026-06-02"
    error_message = "The pool must use the API version that supports provisioning scripts."
  }

  assert {
    condition = (
      azapi_resource.pool.body.properties.fabricProfile.images[0].wellKnownImageName == "ubuntu-24.04-g2" &&
      azapi_resource.pool.body.properties.fabricProfile.images[0].provisioningScriptStorageAccountResourceId == azurerm_storage_account.provisioning.id &&
      azapi_resource.pool.body.properties.fabricProfile.images[0].provisioningScriptEntryPoint == "provisioningscript" &&
      azapi_resource.pool.body.properties.fabricProfile.images[0].provisioningScriptManagedIdentityClientId == "11111111-1111-1111-1111-111111111111" &&
      azapi_resource.pool.body.properties.fabricProfile.images[0].provisioningScriptShouldRestart == false
    )
    error_message = "All provisioning settings must be configured on the Ubuntu image, with the identity's client ID."
  }

  assert {
    condition = (
      azapi_resource.pool.identity[0].type == "UserAssigned" &&
      contains(azapi_resource.pool.identity[0].identity_ids, azurerm_user_assigned_identity.pool.id) &&
      azurerm_role_assignment.script_reader.principal_id == azurerm_user_assigned_identity.pool.principal_id &&
      azurerm_role_assignment.log_writer.principal_id == azurerm_user_assigned_identity.pool.principal_id
    )
    error_message = "The pool and container RBAC must reference the same identity."
  }

  assert {
    condition = (
      azurerm_role_assignment.script_reader.scope == azurerm_storage_container.scripts.id &&
      azurerm_role_assignment.script_reader.role_definition_name == "Storage Blob Data Reader" &&
      azurerm_role_assignment.log_writer.scope == azurerm_storage_container.logs.id &&
      azurerm_role_assignment.log_writer.role_definition_name == "Storage Blob Data Contributor" &&
      azurerm_storage_container.logs.name == "mdpprovisioningscriptlogs"
    )
    error_message = "Use the mandatory log container and least-privilege, container-scoped roles."
  }

  assert {
    condition = (
      azurerm_storage_account.provisioning.account_kind == "StorageV2" &&
      azurerm_storage_account.provisioning.account_tier == "Standard" &&
      !azurerm_storage_account.provisioning.shared_access_key_enabled &&
      !azurerm_storage_account.provisioning.allow_nested_items_to_be_public &&
      azurerm_storage_container.scripts.container_access_type == "private" &&
      azurerm_storage_container.logs.container_access_type == "private"
    )
    error_message = "Provisioning storage must be Standard GPv2, private, and use Microsoft Entra authentication."
  }

  assert {
    condition = (
      azurerm_storage_blob.setup.name == "Setup.sh" &&
      azurerm_storage_blob.setup.storage_container_id == azurerm_storage_container.scripts.id &&
      startswith(azurerm_storage_blob.setup.source_content, "#!/usr/bin/env bash\n") &&
      !strcontains(azurerm_storage_blob.setup.source_content, "\r") &&
      azurerm_storage_blob.setup.content_md5 == md5(azurerm_storage_blob.setup.source_content)
    )
    error_message = "Upload the Linux entry point with LF endings and content-based change detection."
  }

  assert {
    condition = (
      azapi_resource.pool.body.properties.agentProfile.kind == "Stateless" &&
      azapi_resource.pool.body.properties.devCenterProjectResourceId == azurerm_dev_center_project.pool.id &&
      azapi_resource.pool.body.properties.organizationProfile.organizations[0].projects == var.azure_devops_projects &&
      !azapi_resource.pool.body.properties.organizationProfile.organizations[0].openAccess &&
      azapi_resource.pool.body.properties.organizationProfile.permissionProfile.kind == "CreatorOnly"
    )
    error_message = "Keep agents stateless and restrict access to the configured projects and explicitly authorized pipelines."
  }
}

run "restart_and_concurrency" {
  command = apply

  variables {
    restart_after_provisioning = true
    maximum_concurrency        = 3
  }

  assert {
    condition = (
      azapi_resource.pool.body.properties.fabricProfile.images[0].provisioningScriptShouldRestart &&
      azapi_resource.pool.body.properties.maximumConcurrency == 3 &&
      azapi_resource.pool.body.properties.organizationProfile.organizations[0].parallelism == 3
    )
    error_message = "Restart must be configurable and organization parallelism must match pool concurrency."
  }
}

run "reject_fractional_concurrency" {
  command = plan

  variables {
    maximum_concurrency = 1.5
  }

  expect_failures = [var.maximum_concurrency]
}

run "reject_zero_concurrency" {
  command = plan

  variables {
    maximum_concurrency = 0
  }

  expect_failures = [var.maximum_concurrency]
}

run "reject_empty_projects" {
  command = plan

  variables {
    azure_devops_projects = []
  }

  expect_failures = [var.azure_devops_projects]
}
