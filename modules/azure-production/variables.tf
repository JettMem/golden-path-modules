variable "project" {
  description = "The project's key, in lower case (sta): every name starts with it."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{3}$", var.project))
    error_message = "The project's key, three letters, in lower case."
  }
}

variable "location" {
  description = "The Azure region production is in."
  type        = string
  default     = "eastus2"
}

variable "registry" {
  description = "The container registry's name: 5 to 50 letters and digits, unique in all of Azure."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.registry))
    error_message = "5 to 50 lower-case letters and digits."
  }
}

variable "apps" {
  description = "Each deployable app, as infra/preview.yaml names it: the port it listens on and its health address."
  type = map(object({
    port   = number
    health = string
    cpu    = optional(number, 0.25)
    memory = optional(string, "0.5Gi")
  }))
}

variable "migrations" {
  description = "The command that runs the database's migrations from the release's image, or null for none."
  type        = list(string)
  default     = null
}

variable "database_secret" {
  description = <<-EOT
    Whether the apps and the migrations get DATABASE_URL from the vault's `database-url` secret. Apply once with false,
    store the secret at a hidden prompt (README.md), then apply again with true.
  EOT
  type        = bool
  default     = false
}
