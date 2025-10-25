# VPC with /26 CIDR (64 IPs)
resource "aws_vpc" "minecraft_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

# Internet Gateway
resource "aws_internet_gateway" "minecraft_igw" {
  vpc_id = aws_vpc.minecraft_vpc.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

# Public Subnet
resource "aws_subnet" "minecraft_public_subnet" {
  vpc_id                  = aws_vpc.minecraft_vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet"
    Environment = var.environment
  }
}

# Route Table
resource "aws_route_table" "minecraft_public_rt" {
  vpc_id = aws_vpc.minecraft_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.minecraft_igw.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

# Route Table Association
resource "aws_route_table_association" "minecraft_public_rta" {
  subnet_id      = aws_subnet.minecraft_public_subnet.id
  route_table_id = aws_route_table.minecraft_public_rt.id
}

# Data source for EC2 Instance Connect IP ranges
data "aws_ec2_managed_prefix_list" "instance_connect" {
  filter {
    name   = "prefix-list-name"
    values = ["com.amazonaws.${var.aws_region}.ec2-instance-connect"]
  }
}

# Security Group for Minecraft Server
resource "aws_security_group" "minecraft_sg" {
  name        = "${var.project_name}-sg"
  description = "Security group for Minecraft server"
  vpc_id      = aws_vpc.minecraft_vpc.id

  # Minecraft Java Edition port
  ingress {
    description = "Minecraft Java Edition"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access (restricted to your IP if specified)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_ips
  }

  # EC2 Instance Connect
  ingress {
    description     = "EC2 Instance Connect"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.instance_connect.id]
  }

  # RCON port (optional, for remote console)
  ingress {
    description = "RCON"
    from_port   = 25575
    to_port     = 25575
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_ips
  }

  # Outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg"
    Environment = var.environment
  }
}

# Security Group for NLB
resource "aws_security_group" "nlb_sg" {
  name        = "${var.project_name}-nlb-sg"
  description = "Security group for Network Load Balancer"
  vpc_id      = aws_vpc.minecraft_vpc.id

  ingress {
    description = "Minecraft port from anywhere"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-nlb-sg"
    Environment = var.environment
  }
}

# IAM Role for EC2 Instance
resource "aws_iam_role" "minecraft_ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ec2-role"
    Environment = var.environment
  }
}

# IAM Policy for CloudWatch Logs and EBS Snapshots
resource "aws_iam_role_policy" "minecraft_ec2_policy" {
  name = "${var.project_name}-ec2-policy"
  role = aws_iam_role.minecraft_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach SSM policy for Systems Manager access
resource "aws_iam_role_policy_attachment" "minecraft_ssm_policy" {
  role       = aws_iam_role.minecraft_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "minecraft_instance_profile" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.minecraft_ec2_role.name
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints_sg" {
  name        = "${var.project_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.minecraft_vpc.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-vpc-endpoints-sg"
    Environment = var.environment
  }
}

# VPC Endpoint for SSM
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.minecraft_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.minecraft_public_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.project_name}-ssm-endpoint"
    Environment = var.environment
  }
}

# VPC Endpoint for SSM Messages
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.minecraft_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.minecraft_public_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.project_name}-ssmmessages-endpoint"
    Environment = var.environment
  }
}

# VPC Endpoint for EC2 Messages
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.minecraft_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.minecraft_public_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.project_name}-ec2messages-endpoint"
    Environment = var.environment
  }
}

# VPC Endpoint for EC2 (for metadata and Instance Connect)
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.minecraft_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.minecraft_public_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.project_name}-ec2-endpoint"
    Environment = var.environment
  }
}

# User data script for Minecraft installation
locals {
  user_data = templatefile("${path.module}/user_data.sh", {
    max_players    = var.max_players
    server_motd    = var.server_motd
    rcon_password  = var.rcon_password
    server_memory  = var.server_memory
    aws_region     = var.aws_region
  })
}

# EBS Volume for Minecraft data
resource "aws_ebs_volume" "minecraft_data" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = var.ebs_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name        = "${var.project_name}-data"
    Environment = var.environment
    Backup      = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# EC2 Instance
resource "aws_instance" "minecraft_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.minecraft_public_subnet.id
  vpc_security_group_ids = [aws_security_group.minecraft_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.minecraft_instance_profile.name
  user_data              = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "${var.project_name}-server"
    Environment = var.environment
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# Attach EBS volume to instance
resource "aws_volume_attachment" "minecraft_data_attachment" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.minecraft_data.id
  instance_id = aws_instance.minecraft_server.id
}

# Elastic IP
resource "aws_eip" "minecraft_eip" {
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-eip"
    Environment = var.environment
  }
}

# Associate EIP with instance
resource "aws_eip_association" "minecraft_eip_assoc" {
  instance_id   = aws_instance.minecraft_server.id
  allocation_id = aws_eip.minecraft_eip.id
}

# Network Load Balancer
resource "aws_lb" "minecraft_nlb" {
  name               = "${var.project_name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.minecraft_public_subnet.id]

  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.project_name}-nlb"
    Environment = var.environment
  }
}

# NLB Target Group
resource "aws_lb_target_group" "minecraft_tg" {
  name     = "${var.project_name}-tg"
  port     = 25565
  protocol = "TCP"
  vpc_id   = aws_vpc.minecraft_vpc.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = 25565
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = {
    Name        = "${var.project_name}-tg"
    Environment = var.environment
  }
}

# Register instance with target group
resource "aws_lb_target_group_attachment" "minecraft_tg_attachment" {
  target_group_arn = aws_lb_target_group.minecraft_tg.arn
  target_id        = aws_instance.minecraft_server.id
  port             = 25565
}

# NLB Listener
resource "aws_lb_listener" "minecraft_listener" {
  load_balancer_arn = aws_lb.minecraft_nlb.arn
  port              = 25565
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minecraft_tg.arn
  }
}

# Route53 Hosted Zone (data source - assumes zone already exists)
data "aws_route53_zone" "main" {
  count = var.domain_name != "" ? 1 : 0
  name  = var.domain_name
}

# Route53 Record for subdomain pointing to EIP
resource "aws_route53_record" "minecraft_subdomain" {
  count   = var.domain_name != "" && var.subdomain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "${var.subdomain_name}.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.minecraft_eip.public_ip]
}

# DLM (Data Lifecycle Manager) for automated EBS snapshots
resource "aws_iam_role" "dlm_lifecycle_role" {
  name = "${var.project_name}-dlm-lifecycle-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "dlm_lifecycle_policy" {
  name = "${var.project_name}-dlm-lifecycle-policy"
  role = aws_iam_role.dlm_lifecycle_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots",
          "ec2:DeleteSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*::snapshot/*"
      }
    ]
  })
}

# DLM Lifecycle Policy for automatic snapshots
resource "aws_dlm_lifecycle_policy" "minecraft_backup" {
  description        = "Minecraft EBS volume backup policy"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "Daily snapshots"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = var.snapshot_retention_days
      }

      tags_to_add = {
        SnapshotCreator = "DLM"
        Environment     = var.environment
      }

      copy_tags = true
    }

    target_tags = {
      Backup = "true"
    }
  }
}
