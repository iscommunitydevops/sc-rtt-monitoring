output "vm2_public_ip" { value = vultr_instance.vm2.main_ip }
output "vm2_private_ip" { value = vultr_instance.vm2.internal_ip }
output "vm1_public_ip" { value = vultr_instance.vm1.main_ip }
output "vm1_private_ip" { value = vultr_instance.vm1.internal_ip }
output "vpc_cidr" {
  value = format("%s/%d", vultr_vpc.mon.v4_subnet, vultr_vpc.mon.v4_subnet_mask)
}
