locals {
  vpc_net_ip            = cidrhost(var.vpc2_cidr, 0)
  vpc_net_bits          = tonumber(split("/", var.vpc2_cidr)[1])
  allowed_ssh_parts     = split("/", trimspace(var.allowed_cidr_ssh))
  allowed_grafana_parts = split("/", trimspace(var.allowed_cidr_grafana))
}

resource "vultr_vpc" "mon" {
  region         = var.region
  description    = var.vpc2_description
  v4_subnet      = local.vpc_net_ip
  v4_subnet_mask = local.vpc_net_bits
}

resource "vultr_firewall_group" "fg_vm2" {
  description = "fw-vm2-router"
}

resource "vultr_firewall_group" "fg_vm1" {
  description = "fw-vm1-app"
}

resource "vultr_firewall_rule" "vm2_ssh" {
  firewall_group_id = vultr_firewall_group.fg_vm2.id
  ip_type           = "v4"
  protocol          = "tcp"
  port              = "22"
  subnet            = local.allowed_ssh_parts[0]
  subnet_size       = tonumber(local.allowed_ssh_parts[1])
}

resource "vultr_firewall_rule" "vm2_icmp" {
  firewall_group_id = vultr_firewall_group.fg_vm2.id
  ip_type           = "v4"
  protocol          = "icmp"
  subnet            = "0.0.0.0"
  subnet_size       = 0
}

resource "vultr_instance" "vm2" {
  label             = "vm2-router"
  hostname          = "vm2"
  region            = var.region
  plan              = var.plan_vm2
  os_id             = var.os_id
  enable_ipv6       = false
  vpc_ids           = [vultr_vpc.mon.id]
  firewall_group_id = vultr_firewall_group.fg_vm2.id
  user_data         = file("${path.module}/cloud-init/vm2-router.yaml")
  tags              = ["router", "nat", "monitoring"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "vultr_firewall_rule" "vm1_ssh_from_vm2" {
  firewall_group_id = vultr_firewall_group.fg_vm1.id
  ip_type           = "v4"
  protocol          = "tcp"
  port              = "22"
  subnet            = vultr_instance.vm2.internal_ip
  subnet_size       = 32
}

resource "vultr_firewall_rule" "vm1_grafana" {
  firewall_group_id = vultr_firewall_group.fg_vm1.id
  ip_type           = "v4"
  protocol          = "tcp"
  port              = "3000"
  subnet            = local.allowed_grafana_parts[0]
  subnet_size       = tonumber(local.allowed_grafana_parts[1])
}

resource "vultr_firewall_rule" "vm1_icmp" {
  firewall_group_id = vultr_firewall_group.fg_vm1.id
  ip_type           = "v4"
  protocol          = "icmp"
  subnet            = "0.0.0.0"
  subnet_size       = 0
}

locals {
  vm1_userdata = templatefile("${path.module}/cloud-init/vm1-app.tftpl", {
    VPC_CIDR      = var.vpc2_cidr
    VM2_VPC_IP    = vultr_instance.vm2.internal_ip
    INFLUX_ORG    = var.influx_org
    INFLUX_BUCKET = var.influx_bucket
    INFLUX_TOKEN  = var.influx_token
    INFLUX_URL    = var.influx_url
  })
}

resource "vultr_instance" "vm1" {
  label             = "vm1-app"
  hostname          = "vm1"
  region            = var.region
  plan              = var.plan_vm1
  os_id             = var.os_id
  enable_ipv6       = false
  vpc_ids           = [vultr_vpc.mon.id]
  firewall_group_id = vultr_firewall_group.fg_vm1.id
  user_data         = local.vm1_userdata
  tags              = ["app", "telegraf", "influxdb", "grafana"]

  lifecycle {
    create_before_destroy = true
  }
}
