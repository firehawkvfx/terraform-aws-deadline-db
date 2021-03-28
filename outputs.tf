output "instance_name" {
  value = local.instance_name
}
output "private_ip" {
  value = module.deadline_db_vault_client.private_ip
}
output "id" {
  value = module.deadline_db_vault_client.id
}
output "consul_private_dns" {
  value = module.deadline_db_vault_client.consul_private_dns
}