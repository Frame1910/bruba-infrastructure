# Configure the Microsoft Azure Provider
provider "azurerm" {
  subscription_id = "b2f836a2-d6e6-4e8d-856a-c9b10a6f0d92"
  features {}
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "azurerm_client_config" "current" {}

locals {
  container_tag = terraform.workspace == "dev" ? "develop" : "main"
  ui_domain     = terraform.workspace == "prod" ? var.domain_name : "dev.${var.domain_name}"
  api_domain    = terraform.workspace == "prod" ? "api.${var.domain_name}" : "dev.api.${var.domain_name}"

}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.app_name}-${terraform.workspace}"
  location = var.region
}

resource "azurerm_user_assigned_identity" "github_identity" {
  name                = "id-github-${var.app_name}-${terraform.workspace}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_federated_identity_credential" "deploy_ui_images" {
  name                = "deploy-ui-images-${terraform.workspace}"
  resource_group_name = azurerm_resource_group.rg.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.github_identity.id
  subject             = "repo:Frame1910/bruba-ui:environment:${terraform.workspace}"
  depends_on          = [azurerm_user_assigned_identity.github_identity]
}
resource "azurerm_federated_identity_credential" "deploy_api_images" {
  name                = "deploy-api-images-${terraform.workspace}"
  resource_group_name = azurerm_resource_group.rg.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.github_identity.id
  subject             = "repo:Frame1910/bruba-api:environment:${terraform.workspace}"
  depends_on          = [azurerm_user_assigned_identity.github_identity]
}
resource "azurerm_role_assignment" "github_actions" {
  principal_id         = azurerm_user_assigned_identity.github_identity.principal_id
  role_definition_name = "Container Apps Contributor"
  scope                = azurerm_resource_group.rg.id
  depends_on           = [azurerm_user_assigned_identity.github_identity]
}

resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-${var.app_name}-${terraform.workspace}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}


resource "azurerm_mssql_server" "db_server" {
  name                          = "sql-${var.app_name}-${terraform.workspace}"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = "12.0"
  administrator_login           = var.database_admin_user
  administrator_login_password  = var.database_admin_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true
}

resource "azurerm_mssql_database" "db" {
  name         = "sqldb-${var.app_name}-${terraform.workspace}"
  server_id    = azurerm_mssql_server.db_server.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "BasePrice"
  max_size_gb  = 2
  sku_name     = "Basic"
  # geo_backup_enabled = false

  # prevent the possibility of accidental data loss
  lifecycle {
    prevent_destroy = false
  }
}

resource "azurerm_mssql_firewall_rule" "darren_public_ip" {
  name             = "Allow-Darren-Public-IP"
  server_id        = azurerm_mssql_server.db_server.id
  start_ip_address = "144.6.151.23"
  end_ip_address   = "144.6.151.23"
}
resource "azurerm_mssql_firewall_rule" "kuba_public_ip" {
  name             = "Allow-Kuba-Public-IP"
  server_id        = azurerm_mssql_server.db_server.id
  start_ip_address = "180.150.80.216"
  end_ip_address   = "180.150.80.216"
}

locals {
  prisma_connection_string = "sqlserver://${azurerm_mssql_server.db_server.fully_qualified_domain_name}:1433;database=${azurerm_mssql_database.db.name};user=${var.database_admin_user};password=${var.database_admin_password};encrypt=true;TrustServerCertificate=true;"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.app_name}-${terraform.workspace}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-${var.app_name}-${terraform.workspace}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/21"]
  service_endpoints    = ["Microsoft.Sql"]

  # delegation {
  #   name = "container-app-delegation"
  #   service_delegation {
  #     name    = "Microsoft.App/environments"
  #     actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
  #   }
  # }
}

resource "azurerm_mssql_virtual_network_rule" "db_vnet_rule" {
  name      = "Allow-VNet-${var.app_name}-${terraform.workspace}"
  server_id = azurerm_mssql_server.db_server.id
  subnet_id = azurerm_subnet.subnet.id

  depends_on = [azurerm_subnet.subnet]
}

resource "azurerm_container_app_environment" "app_environment" {
  name                       = "cae-${var.app_name}-${terraform.workspace}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  # workload_profile {
  #   name                  = "Consumption"
  #   workload_profile_type = "Consumption"
  # }

  # infrastructure_resource_group_name = "managed-rg-${var.app_name}-${terraform.workspace}"
  infrastructure_subnet_id = azurerm_subnet.subnet.id
}

resource "azurerm_container_app" "api" {
  name                         = "ca-${var.app_name}-api-${terraform.workspace}"
  container_app_environment_id = azurerm_container_app_environment.app_environment.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  ingress {
    allow_insecure_connections = terraform.workspace == "dev" ? true : false
    external_enabled           = true
    target_port                = 3000
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3

    container {
      name   = "api"
      image  = "framed1910/bruba-api:${local.container_tag}"
      cpu    = 0.5
      memory = "1.0Gi"

      env {
        name  = "DATABASE_URL"
        value = local.prisma_connection_string
      }
      env {
        name  = "JWT_SECRET"
        value = var.api_jwt_secret
      }
      env {
        name  = "PORT"
        value = 3000
      }
      env {
        name  = "NODE_ENV"
        value = terraform.workspace == "dev" ? "development" : "production"
      }

      command = ["sh", "-c", "npx prisma generate && npx prisma migrate deploy && node dist/src/main"]
    }
  }
}

resource "azurerm_container_app" "ui" {
  name                         = "ca-${var.app_name}-ui-${terraform.workspace}"
  container_app_environment_id = azurerm_container_app_environment.app_environment.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  ingress {
    allow_insecure_connections = terraform.workspace == "dev" ? true : false
    external_enabled           = true
    target_port                = 80
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3
    container {
      name   = "ui"
      image  = "framed1910/bruba-ui:${local.container_tag}"
      cpu    = 0.5
      memory = "1.0Gi"

      env {
        name  = "API_URL"
        value = "https://${local.api_domain}/api"
      }
      env {
        name  = "NG_APP_ENV"
        value = terraform.workspace == "dev" ? "development" : "production"
      }
      # env {
      #   name  = "PORT"
      #   value = 4200
      # }
      env {
        name  = "NODE_ENV"
        value = terraform.workspace == "dev" ? "development" : "production"
      }
    }
  }
}

resource "azurerm_container_app_custom_domain" "ui_custom_domain" {
  name             = local.ui_domain
  container_app_id = azurerm_container_app.ui.id

  depends_on = [cloudflare_dns_record.ui_cname, cloudflare_dns_record.ui_txt]
  lifecycle {
    ignore_changes = [
      container_app_environment_certificate_id,
      certificate_binding_type
    ]
  }
}

resource "azurerm_container_app_custom_domain" "api_custom_domain" {
  name             = local.api_domain
  container_app_id = azurerm_container_app.api.id

  depends_on = [cloudflare_dns_record.api_cname, cloudflare_dns_record.api_txt]
  lifecycle {
    ignore_changes = [
      container_app_environment_certificate_id,
      certificate_binding_type
    ]
  }
}

# Cloudflare DNS Records
resource "cloudflare_dns_record" "ui_cname" {
  zone_id = var.cloudflare_zone_id
  name    = terraform.workspace == "prod" ? "@" : "dev"
  comment = "UI Container App - ${terraform.workspace}. Managed by Terraform."
  content = azurerm_container_app.ui.ingress[0].fqdn
  proxied = false
  ttl     = 1
  type    = "CNAME"
}
resource "cloudflare_dns_record" "api_cname" {
  zone_id = var.cloudflare_zone_id
  name    = terraform.workspace == "prod" ? "api" : "dev.api"
  content = azurerm_container_app.api.ingress[0].fqdn
  type    = "CNAME"
  proxied = false
  ttl     = 1

  comment = "API Container App - ${terraform.workspace}. Managed by Terraform."
}

# TXT Records for Azure domain validation
resource "cloudflare_dns_record" "ui_txt" {
  zone_id = var.cloudflare_zone_id
  name    = "asuid.${local.ui_domain}"
  content = azurerm_container_app.ui.custom_domain_verification_id
  type    = "TXT"
  ttl     = 300

  comment = "Azure domain validation for UI - ${terraform.workspace}. Managed by Terraform."
}
resource "cloudflare_dns_record" "api_txt" {
  zone_id = var.cloudflare_zone_id
  name    = "asuid.${local.api_domain}"
  content = azurerm_container_app.api.custom_domain_verification_id
  type    = "TXT"
  ttl     = 300

  comment = "Azure domain validation for API - ${terraform.workspace}. Managed by Terraform."
}
