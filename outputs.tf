output "pool_id" {
  description = "ARM resource ID of the Managed DevOps Pool."
  value       = azapi_resource.pool.id
}

output "pool_name" {
  description = "Name to use in the Azure Pipelines pool.name setting."
  value       = azapi_resource.pool.name
}

output "provisioning_identity_client_id" {
  description = "Client ID selected by the provisioning script image settings."
  value       = azurerm_user_assigned_identity.pool.client_id
}

output "script_url" {
  description = "Private blob URL; requires Microsoft Entra authentication."
  value       = azurerm_storage_blob.setup.url
}

output "logs_container_url" {
  description = "Container containing provisioning stdout, stderr, and script copies."
  value       = azurerm_storage_container.logs.url
}
