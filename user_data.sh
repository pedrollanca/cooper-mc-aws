#!/bin/bash
set -e

# Update system
dnf update -y

# Install and start SSM agent
dnf install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install Java 21 (required for Minecraft 1.21+)
dnf install -y java-21-amazon-corretto-headless

# Create minecraft user
useradd -m -r -s /bin/bash minecraft

# Create minecraft directory
mkdir -p /opt/minecraft
chown minecraft:minecraft /opt/minecraft

# Mount EBS volume (only format if not already formatted)
if ! blkid /dev/nvme1n1 | grep -q ext4; then
  mkfs -t ext4 /dev/nvme1n1
fi
mkdir -p /mnt/minecraft-data
mount /dev/nvme1n1 /mnt/minecraft-data || mount -a

# Add to fstab for auto-mount on reboot
UUID=$(blkid -s UUID -o value /dev/nvme1n1)
echo "UUID=$UUID /mnt/minecraft-data ext4 defaults,nofail 0 2" >> /etc/fstab

# Set permissions
chown -R minecraft:minecraft /mnt/minecraft-data

# Download vanilla Minecraft server (latest version)
cd /opt/minecraft
sudo -u minecraft curl -L -o minecraft_server.jar https://piston-data.mojang.com/v1/objects/95495a7f485eedd84ce928cef5e223b757d2f764/server.jar

# Create server directory structure
sudo -u minecraft mkdir -p /mnt/minecraft-data/world

# Accept EULA (only if it doesn't exist)
if [ ! -f /mnt/minecraft-data/eula.txt ]; then
  echo "eula=true" > /mnt/minecraft-data/eula.txt
  chown minecraft:minecraft /mnt/minecraft-data/eula.txt
fi

# Create server.properties (only if it doesn't exist)
if [ ! -f /mnt/minecraft-data/server.properties ]; then
  cat > /mnt/minecraft-data/server.properties <<EOF
server-port=25565
max-players=${max_players}
motd=${server_motd}
enable-rcon=true
rcon.port=25575
rcon.password=${rcon_password}
difficulty=normal
gamemode=survival
pvp=true
spawn-protection=16
max-world-size=29999984
view-distance=10
simulation-distance=10
online-mode=true
white-list=false
EOF
  chown minecraft:minecraft /mnt/minecraft-data/server.properties
fi

# Create systemd service
cat > /etc/systemd/system/minecraft.service <<EOF
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=simple
User=minecraft
WorkingDirectory=/mnt/minecraft-data
ExecStart=/usr/bin/java -Xmx${server_memory} -Xms${server_memory} -jar /opt/minecraft/minecraft_server.jar nogui

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Minecraft server
systemctl daemon-reload
systemctl enable minecraft.service
systemctl start minecraft.service

# Install CloudWatch agent (optional but recommended)
dnf install -y amazon-cloudwatch-agent

# Backups are handled by AWS DLM (Data Lifecycle Manager) - see main.tf
