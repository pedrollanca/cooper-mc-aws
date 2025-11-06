# cooper-mc-aws

Terraform Infrastructure as Code for deploying a Minecraft vanilla server on AWS.

## What It Does

This Terraform configuration deploys a complete Minecraft server infrastructure on AWS with:

- **EC2 Instance**: Amazon Linux 2023 instance running PaperMC server with Java 21
- **Cross-Platform Support**: GeyserMC and Floodgate for Java + Bedrock Edition compatibility
- **Persistent Storage**: Dedicated EBS volume for world data with lifecycle protection
- **Automated Backups**: Daily snapshots via AWS Data Lifecycle Manager (DLM)
- **Networking**: VPC with public subnet, Internet Gateway, and security groups
- **Remote Access**: SSM Session Manager (no SSH keys needed) and optional EC2 Instance Connect
- **Monitoring**: CloudWatch Logs integration for server logs
- **Control API**: Lambda-powered API Gateway endpoints to start/stop the server remotely
- **CloudFront Protection**: Basic authentication and geo-restrictions (US-only access)
- **Email Notifications**: Optional SNS notifications when server starts or stops
- **API Throttling**: Rate limiting to prevent abuse (2 req/s, 5 burst)

## Features

- **Cross-Platform Play**: Java and Bedrock players on the same server using GeyserMC
- **Data Persistence**: EBS volume survives instance recreation, preserving your world data
- **Lifecycle Protection**: EBS volume cannot be accidentally deleted by Terraform
- **Smart Initialization**: User data script detects existing data and won't overwrite it
- **Automatic Backups**: Configurable retention period for daily snapshots
- **RCON Support**: Remote console access for server management
- **Remote Control**: Start/stop/restart server via simple HTTPS endpoints
- **Custom Domain**: Optional Route53 integration for branded URLs
- **Email Alerts**: Get notified when server state changes
- **Secure**: Encrypted EBS volume, restrictive security groups, HTTPS API with TLS 1.2+, basic auth, geo-restrictions, and rate limiting

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

**Infrastructure:**
- `aws_region`: AWS region for deployment
- `instance_type`: EC2 instance size
- `ebs_volume_size`: Storage size for world data
- `snapshot_retention_days`: How long to keep backups

**Minecraft Settings:**
- `server_memory`: RAM allocation for Minecraft
- `max_players`: Maximum concurrent players
- `server_motd`: Server message of the day
- `rcon_password`: RCON remote console password

**Domain & Notifications:**
- `domain_name`: Your Route53 hosted zone (optional)
- `subdomain_name`: Subdomain for API control endpoints (default: "mc")
- `game_subdomain_name`: Subdomain for Minecraft server (default: "play")
- `notification_email`: Email for start/stop alerts (optional)

**API Security:**
- `api_auth_username`: Username for API basic authentication (default: "admin")
- `api_auth_password`: Password for API basic authentication (required, rotate regularly)

## Usage

### Connecting to Minecraft

The server supports both **Java Edition** and **Bedrock Edition** (console) players on the same server!

**Java Edition (PC):**
```
<subdomain>.<domain>:25565
```

**Bedrock Edition (Xbox, PlayStation, Switch, Mobile, Windows 10/11):**
```
<subdomain>.<domain>:19132
```

Or use the public IP from Terraform outputs if no domain configured.

**Note for Bedrock Players:** Your username will have a `.` prefix (e.g., `.PlayerName`). This is normal and allows you to join without a Java Edition account.

### Remote Server Control

Control the server via HTTPS endpoints with basic authentication:

```bash
# Start the server
curl -u admin:yourpassword https://mc-server.yourdomain.com/start

# Stop the server
curl -u admin:yourpassword https://mc-server.yourdomain.com/stop

# Restart the server
curl -u admin:yourpassword https://mc-server.yourdomain.com/restart

# Check server status
curl -u admin:yourpassword https://mc-server.yourdomain.com/status
```

Or visit the URLs in your browser (you'll be prompted for username/password). Each action returns a JSON response and sends an email notification (if configured).

**Security Features:**
- **Basic Authentication**: Username/password protection (configurable in `terraform.tfvars`)
- **Geo-Restriction**: API only accessible from within the United States
- **Rate Limiting**: 2 requests/second with burst of 5 to prevent abuse
- **HTTPS Only**: All traffic encrypted with TLS 1.2+

**Rotating Credentials:**
To change the API password, update `api_auth_username` and `api_auth_password` in `terraform.tfvars` and run `terraform apply`.

### Email Notifications

If you set `notification_email` in your `terraform.tfvars`:

1. After `terraform apply`, AWS will send a confirmation email
2. Click the confirmation link in the email
3. You'll now receive emails when the server starts, stops, or restarts

### Server Management

**Remote Access:**

The infrastructure automatically generates an SSH key pair. After deployment:

```bash
# SSH using the generated key (path shown in terraform outputs)
ssh -i <project-name>-key.pem ec2-user@<server-ip>

# Or copy the exact command from terraform outputs:
terraform output ssh_command
```

Alternatively, use AWS Systems Manager Session Manager (no SSH keys needed):
```bash
aws ssm start-session --target <instance-id> --region <region>
```

**View Logs:**
```bash
sudo journalctl -u minecraft.service -f
```

**Manual Backup:**
```bash
/usr/local/bin/minecraft-backup.sh
```

**Upgrade Paper and Plugins:**
```bash
sudo /usr/local/bin/minecraft-upgrade.sh
```
This script will:
- Stop the Minecraft server gracefully
- Backup current Paper jar and plugins
- Download the latest Paper version for Minecraft 1.21.4
- Update GeyserMC and Floodgate to latest versions
- Restart the server with upgraded software

**Important:** The `.pem` file is automatically gitignored. Keep it secure and don't commit it to version control.
