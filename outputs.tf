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
  value = var.domain_name != "" && var.subdomain_name != "" ? (
    "${var.subdomain_name}.${var.domain_name}"
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

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i <your-key.pem> ec2-user@${aws_eip.minecraft_eip.public_ip}"
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
