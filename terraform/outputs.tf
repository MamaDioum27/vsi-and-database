output "lb_dns_name" {
  description = "Adresse du load balancer (à ouvrir en https://)"
  value       = aws_lb.app.dns_name
}

output "vm_public_ips" {
  description = "IP publiques des VMs (SSH uniquement)"
  value       = { for vm in aws_instance.app : vm.tags.Name => vm.public_ip }
}

output "ssh_commands" {
  description = "Commandes SSH pour chaque VM"
  value       = { for vm in aws_instance.app : vm.tags.Name => "ssh -i ~/.ssh/tp-lb ec2-user@${vm.public_ip}" }
}

output "db_endpoint" {
  description = "Endpoint de la base PostgreSQL"
  value       = aws_db_instance.db.address
}

output "target_group_arn" {
  description = "ARN du target group (pour describe-target-health)"
  value       = aws_lb_target_group.app.arn
}
