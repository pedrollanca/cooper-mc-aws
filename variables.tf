variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS Account ID for resource deployment"
  type        = string
}

variable "aws_role_arn" {
  description = "ARN of the IAM role to assume for Terraform operations"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "minecraft-server"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (/26 = 64 IPs)"
  type        = string
  default     = "10.0.0.0/26"
}

variable "subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.0.0/28"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ebs_volume_size" {
  description = "Size of EBS volume for Minecraft data in GB"
  type        = number
  default     = 20
}

variable "snapshot_retention_days" {
  description = "Number of days to retain EBS snapshots"
  type        = number
  default     = 7
}

variable "ssh_allowed_ips" {
  description = "List of IP addresses allowed to SSH into the server"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Change this to your IP for security
}

variable "domain_name" {
  description = "Main domain name (e.g., example.com) - must exist in Route53"
  type        = string
  default     = ""
}

variable "subdomain_name" {
  description = "Subdomain name for Minecraft server (e.g., mc or minecraft)"
  type        = string
  default     = "mc"
}

variable "max_players" {
  description = "Maximum number of players allowed on the server"
  type        = number
  default     = 20
}

variable "server_motd" {
  description = "Message of the Day shown in server list"
  type        = string
  default     = "A Vanilla Minecraft Server"
}

variable "server_memory" {
  description = "Memory allocation for Minecraft server (e.g., 2G, 4G)"
  type        = string
  default     = "900M" # Suitable for t3.micro (1GB RAM)
}

variable "rcon_password" {
  description = "RCON password for remote console access"
  type        = string
  sensitive   = true
  default     = "changeme123"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for NLB"
  type        = bool
  default     = false
}
