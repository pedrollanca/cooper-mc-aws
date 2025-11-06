output "instance_id" {
  description = "ID of the Minecraft EC2 instance"
  value       = aws_instance.minecraft_server.id
}

output "instance_public_ip" {
  description = "Public IP address of the Minecraft server (Elastic IP)"
  value       = aws_eip.minecraft_eip.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the Minecraft server"
  value       = aws_instance.minecraft_server.private_ip
}

output "minecraft_server_address" {
  description = "Address to connect to the Minecraft server"
  value = var.domain_name != "" && var.game_subdomain_name != "" ? (
    "${var.game_subdomain_name}.${var.domain_name}"
  ) : aws_eip.minecraft_eip.public_ip
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.minecraft_nlb.dns_name
}

output "ebs_volume_id" {
  description = "ID of the EBS volume storing Minecraft data"
  value       = aws_ebs_volume.minecraft_data.id
}

output "security_group_id" {
  description = "ID of the security group for the Minecraft server"
  value       = aws_security_group.minecraft_sg.id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.minecraft_vpc.id
}

output "ssh_key_path" {
  description = "Path to the generated SSH private key"
  value       = local_file.private_key.filename
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i ${local_file.private_key.filename} ec2-user@${aws_eip.minecraft_eip.public_ip}"
}

output "ssm_command" {
  description = "AWS Systems Manager command to connect to the server"
  value       = "aws ssm start-session --target ${aws_instance.minecraft_server.id} --region ${var.aws_region}"
}

output "server_logs_command" {
  description = "Command to view Minecraft server logs"
  value       = "sudo journalctl -u minecraft.service -f"
}

output "backup_volume_command" {
  description = "Command to manually create a snapshot backup"
  value       = "/usr/local/bin/minecraft-backup.sh"
}

output "upgrade_server_command" {
  description = "Command to upgrade Paper and plugins to latest versions"
  value       = "sudo /usr/local/bin/minecraft-upgrade.sh"
}

output "control_api_url" {
  description = "Base URL for the control API"
  value       = var.domain_name != "" && var.subdomain_name != "" ? "https://${var.subdomain_name}.${var.domain_name}" : aws_apigatewayv2_api.control_api.api_endpoint
}

output "start_url" {
  description = "URL to start the Minecraft server"
  value       = var.domain_name != "" && var.subdomain_name != "" ? "https://${var.subdomain_name}.${var.domain_name}/start" : "${aws_apigatewayv2_api.control_api.api_endpoint}/start"
}

output "stop_url" {
  description = "URL to stop the Minecraft server"
  value       = var.domain_name != "" && var.subdomain_name != "" ? "https://${var.subdomain_name}.${var.domain_name}/stop" : "${aws_apigatewayv2_api.control_api.api_endpoint}/stop"
}

output "restart_url" {
  description = "URL to restart the Minecraft server"
  value       = var.domain_name != "" && var.subdomain_name != "" ? "https://${var.subdomain_name}.${var.domain_name}/restart" : "${aws_apigatewayv2_api.control_api.api_endpoint}/restart"
}

output "status_url" {
  description = "URL to check the Minecraft server status"
  value       = var.domain_name != "" && var.subdomain_name != "" ? "https://${var.subdomain_name}.${var.domain_name}/status" : "${aws_apigatewayv2_api.control_api.api_endpoint}/status"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.api_distribution.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.api_distribution.domain_name
}

output "api_auth_info" {
  description = "API authentication information"
  value       = "Use Basic Auth with username from api_auth_username and password from api_auth_password variables"
}
