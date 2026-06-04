resource "random_string" "ecr_acr_suffix" {
  count = var.ecr_source_credentials == null ? 0 : 1

  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_container_registry" "ecr_mirror" {
  #checkov:skip=CKV_AZURE_139:Public access required so apply-time `az acr import` and ACI can pull; private endpoint needs Premium and breaks the import/pull flow.
  #checkov:skip=CKV_AZURE_164:Content trust is Premium-only and deprecated by Azure; not required for this template mirror.
  #checkov:skip=CKV_AZURE_165:Single-region template; geo-replication requires Premium.
  #checkov:skip=CKV_AZURE_166:Image quarantine is a Premium/preview feature; not required for this template.
  #checkov:skip=CKV_AZURE_167:Untagged-manifest retention policy is Premium-only; not required for this template.
  #checkov:skip=CKV_AZURE_233:Zone redundancy requires Premium; consistent with CKV_AZURE_229 already skipped.
  #checkov:skip=CKV_AZURE_237:Dedicated data endpoints are Premium-only; not required for this template.
  count = var.ecr_source_credentials == null ? 0 : 1

  name                = substr("${replace(local.name_prefix_slug, "-", "")}acr${random_string.ecr_acr_suffix[0].result}", 0, 50)
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  admin_enabled       = false

  tags = var.tags
}

resource "azurerm_container_registry_scope_map" "designer_pull" {
  count = var.ecr_source_credentials == null ? 0 : 1

  name                    = "designer-pull"
  resource_group_name     = azurerm_resource_group.rg.name
  container_registry_name = azurerm_container_registry.ecr_mirror[0].name
  actions = [
    "repositories/lontiplatform/martini-designer-online/content/read",
    "repositories/lontiplatform/martini-designer-online/metadata/read",
  ]
}

resource "azurerm_container_registry_token" "aci_designer_pull" {
  count = var.ecr_source_credentials == null ? 0 : 1

  name                    = "aci-designer-pull"
  resource_group_name     = azurerm_resource_group.rg.name
  container_registry_name = azurerm_container_registry.ecr_mirror[0].name
  scope_map_id            = azurerm_container_registry_scope_map.designer_pull[0].id
  enabled                 = true
}

resource "azurerm_container_registry_token_password" "aci_designer_pull" {
  count = var.ecr_source_credentials == null ? 0 : 1

  container_registry_token_id = azurerm_container_registry_token.aci_designer_pull[0].id

  password1 {}
}

# ACR Artifact Cache does not support private AWS ECR as an upstream
# (only public.ecr.aws and a handful of others are allowed). Instead,
# mint a short-lived ECR token at apply time and use `az acr import`
# to copy the image into our ACR. ACI then pulls from ACR using a
# scoped pull-only token, so there is no token-expiry issue at runtime.
data "aws_ecr_authorization_token" "designer" {
  count = var.ecr_source_credentials == null ? 0 : 1

  registry_id = var.ecr_source_credentials.account_id
}

# Force re-import when the tag, ACR, or source repo changes. For mutable
# tags (e.g. a beta tag whose digest changes), force a refresh with:
#   terraform apply -replace=terraform_data.ecr_image_import[0]
resource "terraform_data" "ecr_image_import" {
  count = var.ecr_source_credentials == null ? 0 : 1

  triggers_replace = {
    image_tag   = var.martini_version
    acr_name    = azurerm_container_registry.ecr_mirror[0].name
    source_repo = var.ecr_source_credentials.repository
    account_id  = var.ecr_source_credentials.account_id
    region      = var.ecr_source_credentials.region
  }

  provisioner "local-exec" {
    command = <<-EOT
      az acr import \
        --name "${azurerm_container_registry.ecr_mirror[0].name}" \
        --source "${var.ecr_source_credentials.account_id}.dkr.ecr.${var.ecr_source_credentials.region}.amazonaws.com/${var.ecr_source_credentials.repository}:${var.martini_version}" \
        --image "lontiplatform/martini-designer-online:${var.martini_version}" \
        --username AWS \
        --password "$ECR_TOKEN" \
        --force
    EOT

    environment = {
      ECR_TOKEN = data.aws_ecr_authorization_token.designer[0].password
    }
  }
}
