output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "resource_group_location" {
  value = azurerm_resource_group.rg.location
}

output "martini_ingress_fqdn" {
  value       = local.martini_app_fqdn
  description = "Default *.azurecontainerapps.io FQDN of the Martini app's external ingress (the app's base URL when no custom domain is bound)."
}

output "custom_domain_dns_records" {
  description = "The exact DNS records to create in the zone that owns custom_domain, then set custom_domain_dns_ready = true and re-apply. Null when custom_domain is empty."
  value = local.custom_domain_enabled ? [
    {
      name  = var.custom_domain
      type  = "CNAME"
      value = local.martini_app_fqdn
    },
    {
      name  = "asuid.${var.custom_domain}"
      type  = "TXT"
      value = nonsensitive(var.enable_designer ? azurerm_container_app.martini_designer[0].custom_domain_verification_id : azurerm_container_app.martini[0].custom_domain_verification_id)
    },
  ] : null
}

output "subnet_prefixes" {
  value = local.byo_vnet ? {
    aci       = var.aci_subnet_cidr
    aca       = var.aca_subnet_cidr
    cassandra = var.enable_cassandra_tracker ? var.cassandra_subnet_cidr : null
    } : {
    for name, subnet in module.virtual_network[0].subnets :
    name => subnet.resource.body.properties.addressPrefixes[0]
  }
}

output "cassandra_contact_point" {
  value = var.enable_cassandra_tracker ? local.cassandra_node_fqdns[0] : null
}

output "cassandra_port" {
  value = var.enable_cassandra_tracker ? 9042 : null
}

output "cassandra_cluster_name" {
  value = var.enable_cassandra_tracker ? azurerm_cosmosdb_cassandra_cluster.tracker[0].name : null
}

output "event_hub_namespace_name" {
  value = var.enable_event_hub ? azurerm_eventhub_namespace.this[0].name : null
}

output "event_hub_namespace_fqdn" {
  value = var.enable_event_hub ? "${azurerm_eventhub_namespace.this[0].name}.servicebus.windows.net" : null
}

output "event_hub_names" {
  value = var.enable_event_hub ? sort([for h in azurerm_eventhub.this : h.name]) : []
}

output "log_analytics_workspace_name" {
  value = var.enable_log_analytics ? azurerm_log_analytics_workspace.this[0].name : null
}

output "log_analytics_workspace_id" {
  value = var.enable_log_analytics ? azurerm_log_analytics_workspace.this[0].id : null
}

output "communication_services_smtp_host" {
  value = var.enable_communication_services_email ? "smtp.azurecomm.net" : null
}

output "communication_services_smtp_port" {
  value = var.enable_communication_services_email ? 587 : null
}

output "communication_services_sender_address" {
  value = local.acs_sender_address
}

output "communication_services_email_domain" {
  value = var.enable_communication_services_email ? azurerm_email_communication_service_domain.this[0].from_sender_domain : null
}

output "custom_domain_url" {
  value       = local.custom_domain_enabled ? "https://${var.custom_domain}" : null
  description = "Public HTTPS URL of the custom domain once the CNAME + asuid TXT records are in place and custom_domain_dns_ready = true has issued and bound the managed certificate."
}