# --- Auth ---
variable "vultr_api_key" {
  type = string
}

# --- Infra params ---
variable "region" {
  type    = string
  default = "tlv"
}

variable "os_id" {
  type        = number
  default     = 2284
  description = "Ubuntu 24.04"
}

# SSH public key for instances
variable "ssh_public_key" {
  type = string
}

# --- Plans ---
variable "plan_vm2" {
  type    = string
  default = "vc2-1c-1gb"
}

variable "plan_vm1" {
  type    = string
  default = "vc2-1c-2gb"
}

# --- VPC2 ---
variable "vpc2_description" {
  type    = string
  default = "mon-net"
}

variable "vpc2_cidr" {
  type    = string
  default = "10.10.1.0/24"
}


variable "allowed_cidr_ssh" {
  type        = string
  description = "CIDR for SSH, e.g. 203.0.113.5/32"
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+/\\d{1,2}$", var.allowed_cidr_ssh))
    error_message = "allowed_cidr_ssh must be IPv4 CIDR like X.X.X.X/32."
  }
}

variable "allowed_cidr_grafana" {
  type        = string
  description = "CIDR for Grafana, e.g. 203.0.113.5/32"
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+/\\d{1,2}$", var.allowed_cidr_grafana))
    error_message = "allowed_cidr_grafana must be IPv4 CIDR like X.X.X.X/32."
  }
}

# --- App settings ---
variable "influx_org" {
  type    = string
  default = "netprobe"
}

variable "influx_bucket" {
  type    = string
  default = "netprobe"
}

variable "influx_token" {
  type = string
  sensitive = true 
}

variable "influx_url" {
  type    = string
  default = "http://influxdb:8086"
}