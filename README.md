# cooper-mc-aws

Terraform Infrastructure as Code for deploying a Minecraft vanilla server on AWS.

## What It Does

This Terraform configuration deploys a complete Minecraft server infrastructure on AWS with:

- **EC2 Instance**: Amazon Linux 2023 instance running vanilla Minecraft server with Java 21
- **Persistent Storage**: Dedicated EBS volume for world data with lifecycle protection
- **Automated Backups**: Daily snapshots via AWS Data Lifecycle Manager (DLM)
- **Networking**: VPC with public subnet, Internet Gateway, and security groups
- **Remote Access**: SSM Session Manager (no SSH keys needed) and optional EC2 Instance Connect
- **Monitoring**: CloudWatch Logs integration for server logs

## Features

- **Data Persistence**: EBS volume survives instance recreation, preserving your world data
- **Lifecycle Protection**: EBS volume cannot be accidentally deleted by Terraform
- **Smart Initialization**: User data script detects existing data and won't overwrite it
- **Automatic Backups**: Configurable retention period for daily snapshots
- **RCON Support**: Remote console access for server management
- **Secure**: Encrypted EBS volume, restrictive security groups

## Prerequisites

- AWS account
- Terraform installed
- AWS credentials configured

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and configure variables
2. Run `terraform init`
3. Run `terraform plan` to review changes
4. Run `terraform apply` to deploy

## Configuration

Key variables in `terraform.tfvars`:
- `aws_region`: AWS region for deployment
- `instance_type`: EC2 instance size
- `server_memory`: RAM allocation for Minecraft
- `max_players`: Maximum concurrent players
- `ebs_volume_size`: Storage size for world data
- `snapshot_retention_days`: How long to keep backups

## Connecting

After deployment:
- Minecraft server: `<output-public-ip>:25565`
- Remote management: AWS Systems Manager Session Manager via AWS Console
