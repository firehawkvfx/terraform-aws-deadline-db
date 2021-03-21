output "private_ip" {
  value = module.deadline_db_vault_client.private_ip
}

output "id" {
  value = module.deadline_db_vault_client.id
}

output "consul_private_dns" {
  value = module.deadline_db_vault_client.consul_private_dns
}

# output "instructions" {
#   value = "This host can be used to forward the vault UI to your remote onsite web browser (address https://127.0.0.1:8200/ui) via the bastion by forwarding the web service. From your remote host, enable forwarding with: ssh -J centos@${var.bastion_public_dns} centos@${module.deadline_db_vault_client.consul_private_dns} -L 8200:vault.service.consul:8200"
# }