Managed DevOps Pools provisioning scripts with Terraform
=======================================================

This Windows-oriented example creates a stateless Ubuntu 24.04 Generation 2
pool, a new Dev Center and project, a user-assigned managed identity, and a
Standard StorageV2 account with private script and log containers.

AzureRM manages the supporting resources. AzAPI exclusively manages the pool
using Microsoft.DevOpsInfrastructure/pools@2026-06-02 and an HCL object body
(AzAPI 2.x; do not jsonencode the body).

The provisioning-script feature is in preview. Microsoft documents support
starting at API version 2026-06-02. Updating the same pool with an older API
version can erase these settings. Do not additionally manage this pool through
an AzureRM pool resource or an older API-version update resource.

Prerequisites
-------------
1. Install Terraform >= 1.7 and Azure CLI, then sign in with az login.
2. Use an existing Azure DevOps organization and project. The organization must
   be connected to the appropriate Microsoft Entra tenant. Grant the deploying
   identity the pool-creation permissions described in Microsoft's prerequisites
   (organization owner, or the documented delegated organization/project roles).
   For CI, the service principal/managed identity also needs Azure DevOps access;
   the pool's blob-access identity is not automatically your deployment identity.
3. The deploying identity needs Contributor to create the Azure resources, plus
   permission to assign roles (e.g. Role Based Access Control Administrator).
   Owner includes both. It also needs Storage Blob Data Contributor inherited
   from the subscription (or another preconfigured containing scope) to upload
   Setup.sh. Azure Owner/Contributor alone does NOT grant blob data access.
   Grant these permissions before deployment and allow RBAC propagation.
4. Register Microsoft.DevOpsInfrastructure, Microsoft.DevCenter,
   Microsoft.Storage, and Microsoft.ManagedIdentity in your subscription.
   Provider auto-registration is disabled in this example.
5. Confirm Managed DevOps Pools availability and VM-family quota in the region.
   Azure DevOps parallel-job entitlement must also cover the intended concurrency.

Deployment (PowerShell)
-----------------------
Copy-Item .\terraform.tfvars.example .\terraform.tfvars

Edit terraform.tfvars: replace the subscription, organization, and project
placeholders, and choose globally unique storage account and pool names.
Customize scripts\Setup.sh before deployment.

az login
az account set --subscription "<subscription-id>"
az provider register --namespace Microsoft.DevOpsInfrastructure --wait
az provider register --namespace Microsoft.DevCenter --wait
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.ManagedIdentity --wait

terraform init
terraform fmt -check
terraform validate
terraform test
terraform plan -out=mdp.tfplan
terraform apply mdp.tfplan

The providers use the same subscription and Azure CLI login. For CI use the
providers' supported OIDC authentication settings/environment variables instead;
do not put client secrets in tfvars. Use a protected remote state backend for
shared/production deployments. Commit .terraform.lock.hcl to pin tested versions.

Storage and identity
--------------------
- provisioningScriptEntryPoint is the NAME OF THE SCRIPT CONTAINER
  ("provisioningscript"), not a file name. Managed DevOps Pools downloads the
  whole container and always runs the case-sensitive Setup.sh (Linux) from it.
- mdpprovisioningscriptlogs is the mandatory log container name.
- The pool identity has Storage Blob Data Reader on the script container and
  Storage Blob Data Contributor on the log container, not on the whole account.
- provisioningScriptManagedIdentityClientId is the identity's CLIENT ID, not its
  principal/object ID or ARM resource ID. principal_id is used for RBAC.
- Shared Key access is disabled. Terraform uses Microsoft Entra blob access;
  the pool also downloads scripts and uploads logs using its managed identity.
- The storage network endpoint is public, but containers are private and require
  authentication. This simple example does not inject the agents into a VNet.
  If adding storage firewalls/private endpoints, configure both agent and
  Terraform-runner connectivity/DNS; disabling public access alone will break it.
- Script upload and both role assignments precede pool creation. Azure RBAC is
  eventually consistent: dependency ordering does not guarantee immediate access.

Script behavior and verification
--------------------------------
The sample script logs the hostname and kernel information, then writes
/opt/mdp-provisioning/ready.txt using passwordless sudo on the Ubuntu image.
It is safe to run repeatedly and exits nonzero on failure. Replace it with your
own idempotent installation/configuration steps; do not merely export variables
and expect those exports to persist into an independent agent/job process.

The upload normalizes CRLF to LF for Bash. content_md5 detects edits to Setup.sh.
For additional supporting files, create additional azurerm_storage_blob resources
in the scripts container and include them in the pool's depends_on.
Do not store credentials in scripts or print them: logs contain script copies.

After apply, authorize your pipeline to use the pool (openAccess is false).
Run this job in one of the configured projects, replacing the pool name:

pool:
  name: replace-with-unique-pool-name
steps:
- bash: |
    test -f /opt/mdp-provisioning/ready.txt
    cat /opt/mdp-provisioning/ready.txt
  displayName: Verify provisioning script ran

Inspect the logs_container_url output and its machine-specific directories for
stdout/stderr and the executed script. A successful Terraform apply alone does
not prove that an agent ran the script; the pipeline check is the runtime test.
The local Terraform tests use mocked providers and deploy nothing.

Scripts execute during agent startup, before jobs are assigned. Uploading a new
script does not execute it on agents that are already running. Verify changes
on a newly provisioned agent. restart_after_provisioning defaults to false; only
enable it when your changes require a restart. Let Managed DevOps Pools perform
the restart rather than rebooting directly from the script.

On download/access/upload failures, check identity attachment, client ID, role
scopes and propagation, storage networking, and exact container/blob names.
On execution failures inspect stderr.log. Configure log retention for production;
Managed DevOps Pools does not automatically manage provisioning log retention.

References
----------
https://learn.microsoft.com/en-us/azure/devops/managed-devops-pools/configure-provisioning-scripts?view=azure-devops
https://learn.microsoft.com/en-us/azure/templates/microsoft.devopsinfrastructure/2026-06-02/pools
https://learn.microsoft.com/en-us/azure/devops/managed-devops-pools/prerequisites?view=azure-devops
https://learn.microsoft.com/en-us/azure/devops/managed-devops-pools/configure-images?view=azure-devops
