# cooper-mc-aws

Terraform Infrastructure as Code for deploying a flexible Minecraft server on AWS with support for Vanilla, Paper, or Fabric (modded).

## What It Does

This Terraform configuration deploys a complete Minecraft server infrastructure on AWS with:

- **EC2 Instance**: Amazon Linux 2023 instance with Java 21
- **Flexible Server Types**: Choose Vanilla, Paper (with plugins), or Fabric (with mods)
- **Cross-Platform Support**: Optional GeyserMC plugin for Java + Bedrock Edition compatibility (Paper)
- **Mod Support**: Fabric loader with customizable mod downloads (Cobblemon, Xaero's Minimap, etc.)
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

- **Multiple Server Types**: Choose Vanilla, Paper (plugins), or Fabric (mods)
- **Modding Support**: Easy mod/plugin installation via URL lists
- **Cross-Platform Play**: Optional GeyserMC support for Java and Bedrock players (Paper)
- **Data Persistence**: EBS volume survives instance recreation, preserving your world data
- **Lifecycle Protection**: EBS volume cannot be accidentally deleted by Terraform
- **Smart Initialization**: User data script detects existing data and won't overwrite it
- **Automatic Backups**: Configurable retention period for daily snapshots
- **RCON Support**: Remote console access for server management
- **Auto-Admin**: Automatically grant op permissions to specified player
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
- `minecraft_version`: Minecraft version (e.g., "1.21.1")
- `server_type`: "vanilla", "paper", or "fabric"
- `server_memory`: RAM allocation for Minecraft
- `max_players`: Maximum concurrent players
- `server_motd`: Server message of the day
- `rcon_password`: RCON remote console password
- `admin_username`: Minecraft username to auto-op

**Server Type Specific:**

*For Vanilla:*
- `server_jar_url`: (Optional) Custom server jar URL

*For Paper:*
- `server_jar_url`: (Optional) Custom Paper jar URL
- `plugin_urls`: List of plugin download URLs

*For Fabric:*
- `fabric_loader_version`: Fabric loader version (e.g., "0.18.4")
- `fabric_installer_version`: Fabric installer version (e.g., "1.1.0")
- `mod_urls`: List of mod download URLs

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

**Java Edition (PC):**
```
<subdomain>.<domain>:25565
```

Or use the public IP from Terraform outputs if no domain configured.

**Bedrock Edition (Xbox, PlayStation, Switch, Mobile, Windows 10/11):**

For cross-platform support, use Paper server with GeyserMC plugin:
```
<subdomain>.<domain>:19132
```

**Note for Bedrock Players:** Your username will have a `.` prefix (e.g., `.PlayerName`). This is normal and allows you to join without a Java Edition account.

### Server Type Examples

**Vanilla Server (Pure Minecraft):**
```hcl
server_type = "vanilla"
minecraft_version = "1.21.1"
```

**Paper Server (Plugins + Bedrock Support):**
```hcl
server_type = "paper"
minecraft_version = "1.21.1"
plugin_urls = [
  "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot",
  "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"
]
```

**Fabric Server (Mods like Cobblemon):**
```hcl
server_type = "fabric"
minecraft_version = "1.21.1"
fabric_loader_version = "0.18.4"
mod_urls = [
  "https://cdn.modrinth.com/data/P7dR8mSH/versions/m6zu1K31/fabric-api-0.116.7+1.21.1.jar",
  "https://cdn.modrinth.com/data/MdwFAVRL/versions/s64m1opn/Cobblemon-fabric-1.7.1+1.21.1.jar",
  "https://cdn.modrinth.com/data/1bokaNcj/versions/X2u4L3vW/Xaeros_Minimap_24.3.0_Fabric_1.21.jar"
]
```

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

**Upgrading Server/Mods/Plugins:**

To upgrade your server, mods, or plugins:
1. Update the relevant variables in `terraform.tfvars`:
   - Change `minecraft_version`, `fabric_loader_version`, or update URLs in `mod_urls`/`plugin_urls`
2. Run `terraform apply`
3. The server will be recreated with new configuration

**Note:** The EBS volume with your world data persists across updates.

**Important:** The `.pem` file is automatically gitignored. Keep it secure and don't commit it to version control.

### RCON Access

Remotely manage your server using RCON:

**From your local machine (macOS):**
```bash
brew install mcrcon
mcrcon -H <server-ip> -p 25575 -P <rcon-password> "op <your_username>"
```

**From the server:**
```bash
mcrcon -H localhost -p 25575 -P <rcon-password>
```

Common RCON commands:
- `op <username>` - Grant admin permissions
- `list` - List online players
- `save-all` - Force save world
- `stop` - Stop the server
