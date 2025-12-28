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

  # Minecraft Bedrock Edition port (for GeyserMC)
  ingress {
    description = "Minecraft Bedrock Edition"
    from_port   = 19132
    to_port     = 19132
    protocol    = "udp"
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

# Get latest Amazon Linux 2023 AMI for ARM64 (Graviton)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Generate SSH key pair
resource "tls_private_key" "minecraft_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096

  lifecycle {
    create_before_destroy = true
  }
}

# Create AWS key pair
resource "aws_key_pair" "minecraft_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.minecraft_ssh_key.public_key_openssh

  tags = {
    Name        = "${var.project_name}-key"
    Environment = var.environment
  }
}

# Save private key to local file
resource "local_file" "private_key" {
  content         = tls_private_key.minecraft_ssh_key.private_key_pem
  filename        = "${path.module}/${var.project_name}-key.pem"
  file_permission = "0600"
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
    max_players              = var.max_players
    server_motd              = var.server_motd
    rcon_password            = var.rcon_password
    server_memory            = var.server_memory
    aws_region               = var.aws_region
    admin_username           = var.admin_username
    minecraft_version        = var.minecraft_version
    server_type              = var.server_type
    server_jar_url           = var.server_jar_url
    fabric_loader_version    = var.fabric_loader_version
    fabric_installer_version = var.fabric_installer_version
    mod_urls                 = join(",", var.mod_urls)
    plugin_urls              = join(",", var.plugin_urls)
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
  key_name               = aws_key_pair.minecraft_key.key_name
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

# NLB Listener for Java Edition
resource "aws_lb_listener" "minecraft_listener" {
  load_balancer_arn = aws_lb.minecraft_nlb.arn
  port              = 25565
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minecraft_tg.arn
  }
}

# NLB Target Group for Bedrock Edition
resource "aws_lb_target_group" "minecraft_bedrock_tg" {
  name     = "${var.project_name}-bedrock-tg"
  port     = 19132
  protocol = "UDP"
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
    Name        = "${var.project_name}-bedrock-tg"
    Environment = var.environment
  }
}

# Register instance with Bedrock target group
resource "aws_lb_target_group_attachment" "minecraft_bedrock_tg_attachment" {
  target_group_arn = aws_lb_target_group.minecraft_bedrock_tg.arn
  target_id        = aws_instance.minecraft_server.id
  port             = 19132
}

# NLB Listener for Bedrock Edition
resource "aws_lb_listener" "minecraft_bedrock_listener" {
  load_balancer_arn = aws_lb.minecraft_nlb.arn
  port              = 19132
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minecraft_bedrock_tg.arn
  }
}

# Route53 Hosted Zone (data source - assumes zone already exists)
data "aws_route53_zone" "main" {
  count = var.domain_name != "" ? 1 : 0
  name  = var.domain_name
}

# Route53 Record for Minecraft server (separate from API)
resource "aws_route53_record" "minecraft_server" {
  count   = var.domain_name != "" && var.game_subdomain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "${var.game_subdomain_name}.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.minecraft_eip.public_ip]
}

# Note: The subdomain (e.g., mc.cooperisland7.com) is used for API Gateway control endpoints
# Minecraft game traffic uses game_subdomain (e.g., play.cooperisland7.com) which points directly to the EIP

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

# SNS Topic for notifications
resource "aws_sns_topic" "server_notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-notifications"

  tags = {
    Name        = "${var.project_name}-notifications"
    Environment = var.environment
  }
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "email_subscription" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.server_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM Role for Lambda function
resource "aws_iam_role" "lambda_control_role" {
  name = "${var.project_name}-lambda-control-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-lambda-control-role"
    Environment = var.environment
  }
}

# IAM Policy for Lambda to control EC2 instance
resource "aws_iam_role_policy" "lambda_control_policy" {
  name = "${var.project_name}-lambda-control-policy"
  role = aws_iam_role.lambda_control_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:RebootInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.notification_email != "" ? aws_sns_topic.server_notifications[0].arn : "*"
      }
    ]
  })
}

# Lambda function for start/stop control
resource "aws_lambda_function" "instance_control" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${var.project_name}-control"
  role          = aws_iam_role.lambda_control_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      INSTANCE_ID = aws_instance.minecraft_server.id
      SNS_TOPIC_ARN = var.notification_email != "" ? aws_sns_topic.server_notifications[0].arn : ""
    }
  }

  tags = {
    Name        = "${var.project_name}-control"
    Environment = var.environment
  }
}

# Lambda function code
resource "local_file" "lambda_code" {
  content  = <<-EOF
import json
import boto3
import os

ec2 = boto3.client('ec2')
sns = boto3.client('sns')
instance_id = os.environ['INSTANCE_ID']
sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '')

def send_notification(subject, message):
    if sns_topic_arn:
        try:
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject=subject,
                Message=message
            )
        except Exception as e:
            print(f"Failed to send notification: {str(e)}")

def handler(event, context):
    path = event.get('rawPath', event.get('path', ''))
    action = path.strip('/').lower()

    try:
        if action == 'start':
            ec2.start_instances(InstanceIds=[instance_id])
            send_notification(
                'Minecraft Server Starting',
                f'The Minecraft server is starting.\n\nInstance ID: {instance_id}\n\nThe server will be ready in a few minutes.'
            )
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'message': 'Starting instance', 'instance_id': instance_id})
            }
        elif action == 'stop':
            ec2.stop_instances(InstanceIds=[instance_id])
            send_notification(
                'Minecraft Server Stopping',
                f'The Minecraft server is stopping.\n\nInstance ID: {instance_id}\n\nThe server will be offline shortly.'
            )
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'message': 'Stopping instance', 'instance_id': instance_id})
            }
        elif action == 'restart':
            ec2.reboot_instances(InstanceIds=[instance_id])
            send_notification(
                'Minecraft Server Restarting',
                f'The Minecraft server is restarting.\n\nInstance ID: {instance_id}\n\nThe server will be back online in a few minutes.'
            )
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'message': 'Restarting instance', 'instance_id': instance_id})
            }
        elif action == 'status':
            response = ec2.describe_instances(InstanceIds=[instance_id])
            state = response['Reservations'][0]['Instances'][0]['State']['Name']
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'instance_id': instance_id, 'state': state})
            }
        else:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Invalid action. Use /start, /stop, /restart, or /status'})
            }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }
EOF
  filename = "${path.module}/lambda/index.py"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "${path.module}/lambda/function.zip"
  depends_on  = [local_file.lambda_code]
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "control_api" {
  name          = "${var.project_name}-control-api"
  protocol_type = "HTTP"
  description   = "API for controlling Minecraft server instance"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["*"]
  }

  tags = {
    Name        = "${var.project_name}-control-api"
    Environment = var.environment
  }
}

# API Gateway integration with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.control_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.instance_control.invoke_arn
  payload_format_version = "2.0"
}

# API Gateway routes
resource "aws_apigatewayv2_route" "start_route" {
  api_id    = aws_apigatewayv2_api.control_api.id
  route_key = "GET /start"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "stop_route" {
  api_id    = aws_apigatewayv2_api.control_api.id
  route_key = "GET /stop"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "restart_route" {
  api_id    = aws_apigatewayv2_api.control_api.id
  route_key = "GET /restart"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "status_route" {
  api_id    = aws_apigatewayv2_api.control_api.id
  route_key = "GET /status"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.control_api.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 5
    throttling_rate_limit  = 2
  }

  tags = {
    Name        = "${var.project_name}-default-stage"
    Environment = var.environment
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_control.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.control_api.execution_arn}/*/*"
}

# ACM Certificate for custom domain (only if domain is configured)
resource "aws_acm_certificate" "api_cert" {
  count             = var.domain_name != "" && var.subdomain_name != "" ? 1 : 0
  domain_name       = "${var.subdomain_name}.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-api-cert"
    Environment = var.environment
  }
}

# ACM Certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = var.domain_name != "" && var.subdomain_name != "" ? {
    for dvo in aws_acm_certificate.api_cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main[0].zone_id
}

resource "aws_acm_certificate_validation" "api_cert_validation" {
  count                   = var.domain_name != "" && var.subdomain_name != "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.api_cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# API Gateway custom domain
resource "aws_apigatewayv2_domain_name" "api_domain" {
  count       = var.domain_name != "" && var.subdomain_name != "" ? 1 : 0
  domain_name = "${var.subdomain_name}.${var.domain_name}"

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.api_cert[0].arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  depends_on = [aws_acm_certificate_validation.api_cert_validation]

  tags = {
    Name        = "${var.project_name}-api-domain"
    Environment = var.environment
  }
}

# API Gateway domain mapping
resource "aws_apigatewayv2_api_mapping" "api_mapping" {
  count       = var.domain_name != "" && var.subdomain_name != "" ? 1 : 0
  api_id      = aws_apigatewayv2_api.control_api.id
  domain_name = aws_apigatewayv2_domain_name.api_domain[0].id
  stage       = aws_apigatewayv2_stage.default_stage.id
}

# CloudFront Function for Basic Authentication
resource "aws_cloudfront_function" "basic_auth" {
  name    = "${var.project_name}-basic-auth"
  runtime = "cloudfront-js-2.0"
  comment = "Basic authentication for API endpoints"
  publish = true
  code    = <<-EOF
function handler(event) {
  var req = event.request;
  var auth = req.headers['authorization'] && req.headers['authorization'].value;

  var expected = "Basic ${base64encode("${var.api_auth_username}:${var.api_auth_password}")}";

  if (auth !== expected) {
    return {
      statusCode: 401,
      statusDescription: 'Unauthorized',
      headers: { 'www-authenticate': { value: 'Basic realm="API Authentication Required"' } }
    };
  }

  return req;
}
EOF
}

# CloudFront Origin Access Control for API Gateway
resource "aws_cloudfront_origin_access_control" "api_gateway" {
  name                              = "${var.project_name}-api-gateway-oac"
  description                       = "Origin access control for API Gateway"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "no-override"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "api_distribution" {
  enabled             = true
  comment             = "${var.project_name} API distribution with basic auth"
  aliases             = var.domain_name != "" && var.subdomain_name != "" ? ["${var.subdomain_name}.${var.domain_name}"] : []
  price_class         = "PriceClass_100"
  default_root_object = ""

  origin {
    domain_name = var.domain_name != "" && var.subdomain_name != "" ? aws_apigatewayv2_domain_name.api_domain[0].domain_name_configuration[0].target_domain_name : replace(aws_apigatewayv2_api.control_api.api_endpoint, "https://", "")
    origin_id   = "api-gateway"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "api-gateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Host"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.basic_auth.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.domain_name == "" || var.subdomain_name == "" ? true : false
    acm_certificate_arn            = var.domain_name != "" && var.subdomain_name != "" ? aws_acm_certificate.api_cert[0].arn : null
    ssl_support_method             = var.domain_name != "" && var.subdomain_name != "" ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = {
    Name        = "${var.project_name}-api-distribution"
    Environment = var.environment
  }
}

# Update Route53 to point API subdomain to CloudFront (instead of API Gateway directly)
resource "aws_route53_record" "api_alias" {
  count   = var.domain_name != "" && var.subdomain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "${var.subdomain_name}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.api_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.api_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
