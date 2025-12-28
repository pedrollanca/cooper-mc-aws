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
  description = "EC2 instance type (Graviton/ARM64)"
  type        = string
  default     = "t4g.medium"
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
  description = "Subdomain name for API control endpoints (e.g., mc or api)"
  type        = string
  default     = "mc"
}

variable "game_subdomain_name" {
  description = "Subdomain name for Minecraft game server (e.g., play or game)"
  type        = string
  default     = "play"
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

variable "admin_username" {
  description = "Minecraft username to grant admin (op) permissions"
  type        = string
  default     = ""
}

variable "minecraft_version" {
  description = "Minecraft version to install"
  type        = string
  default     = "1.21.1"
}

variable "server_type" {
  description = "Server type: vanilla, paper, or fabric"
  type        = string
  default     = "fabric"
  validation {
    condition     = contains(["vanilla", "paper", "fabric"], var.server_type)
    error_message = "Server type must be vanilla, paper, or fabric."
  }
}

variable "server_jar_url" {
  description = "URL to download server jar (only for vanilla or paper). Leave empty for fabric."
  type        = string
  default     = ""
}

variable "fabric_loader_version" {
  description = "Fabric loader version (only used if server_type is fabric)"
  type        = string
  default     = "0.18.4"
}

variable "fabric_installer_version" {
  description = "Fabric installer version (only used if server_type is fabric)"
  type        = string
  default     = "1.1.0"
}

variable "mod_urls" {
  description = "List of mod URLs to download (for Fabric)"
  type        = list(string)
  default     = []
}

variable "plugin_urls" {
  description = "List of plugin URLs to download (for Paper)"
  type        = list(string)
  default     = []
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for NLB"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address to receive notifications when server starts/stops"
  type        = string
  default     = ""
}

variable "api_auth_username" {
  description = "Username for API basic authentication"
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "api_auth_password" {
  description = "Password for API basic authentication"
  type        = string
  sensitive   = true
}
