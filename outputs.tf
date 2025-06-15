output "db_fqdn" {
  description = "The fully qualified domain name of the database instance."
  value       = azurerm_mssql_server.db_server.fully_qualified_domain_name
}
output "db_name" {
  description = "The name of the database."
  value       = azurerm_mssql_database.db.name
}
output "db_admin_username" {
  description = "The admin username for the database."
  value       = azurerm_mssql_server.db_server.administrator_login
}
output "db_admin_password" {
  description = "The admin password for the database."
  value       = azurerm_mssql_server.db_server.administrator_login_password
  sensitive   = true
}

output "api_container_fqdn" {
  description = "The fully qualified domain name of the API container."
  value       = azurerm_container_app.api.ingress[0].fqdn
}
output "ui_container_fqdn" {
  description = "The fully qualified domain name of the UI container."
  value       = azurerm_container_app.ui.ingress[0].fqdn
}

output "api_url" {
  description = "The URL of the API container."
  value       = "http://${local.api_domain}/api"
}
output "ui_url" {
  description = "The URL of the UI container."
  value       = "http://${local.ui_domain}"
}
