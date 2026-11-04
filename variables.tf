variable "subscription_id" {
  type        = string
  description = "Azure subscription in which to deploy the resources."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a UUID."
  }
}

variable "location" {
  type        = string
  description = "Azure region supporting Managed DevOps Pools and the selected VM size."
  default     = "eastus"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for the resource group, Dev Center, project, and managed identity."
  default     = "mdpdemo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.name_prefix))
    error_message = "name_prefix must be 3-20 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "pool_name" {
  type        = string
  description = "Globally unique Managed DevOps Pool name; also the Azure Pipelines pool name."
  default     = "mdp-demo-ubuntu"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{3,44}$", var.pool_name))
    error_message = "pool_name must be 3-44 alphanumeric characters, dots, underscores, or hyphens."
  }
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique name of the provisioning script storage account."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase letters or digits."
  }
}

variable "azure_devops_organization_url" {
  type        = string
  description = "Azure DevOps organization URL, for example https://dev.azure.com/my-organization."

  validation {
    condition     = can(regex("^https://dev\\.azure\\.com/[a-zA-Z0-9-]+/?$", var.azure_devops_organization_url))
    error_message = "Use an organization URL in the form https://dev.azure.com/my-organization."
  }
}

variable "azure_devops_projects" {
  type        = list(string)
  description = "Existing Azure DevOps project names allowed to use the pool."

  validation {
    condition     = length(var.azure_devops_projects) > 0 && alltrue([for project in var.azure_devops_projects : trimspace(project) != ""])
    error_message = "Specify at least one non-empty Azure DevOps project name."
  }
}

variable "maximum_concurrency" {
  type        = number
  description = "Maximum concurrent agents; also the parallelism allocated to the organization."
  default     = 1

  validation {
    condition     = var.maximum_concurrency >= 1 && floor(var.maximum_concurrency) == var.maximum_concurrency
    error_message = "maximum_concurrency must be a positive integer."
  }
}

variable "vm_size" {
  type        = string
  description = "Generation 2-compatible VM size with available Managed DevOps Pools quota."
  default     = "Standard_D2ads_v5"
}

variable "restart_after_provisioning" {
  type        = bool
  description = "Restart the agent after Setup.sh completes, before it receives a job."
  default     = false
}
