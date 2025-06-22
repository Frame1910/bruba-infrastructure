variable "app_name" {
  description = "The name of the application"
  type        = string
  default     = "bruba-wedding-app"
}

variable "region" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "australiaeast"
}

variable "database_admin_user" {
  description = "The administrator username for the SQL database"
  type        = string
  default     = "mssql_administrator"
}

variable "database_admin_password" {
  description = "The administrator password for the SQL database"
  type        = string
  sensitive   = true
  default     = "kBc6yG77zbjelv"
}

variable "domain_name" {
  description = "Your existing domain name"
  type        = string
  default     = "bruba.wedding"
}


variable "cloudflare_api_token" {
  description = "Cloudflare API token with permissions to manage DNS records"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for managing DNS records"
  type        = string
  default     = "4194217e56e6eeef110c667fb20eee18"
}

variable "api_jwt_secret" {
  description = "Secret used to sign JWT tokens for API authentication"
  type        = string
  sensitive   = true

}
