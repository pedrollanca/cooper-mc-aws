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

# Download GeyserMC (allows Bedrock players to join)
cd /opt/minecraft
sudo -u minecraft mkdir -p plugins
sudo -u minecraft curl -L -o plugins/Geyser-Spigot.jar https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot

# Download Floodgate (allows Bedrock players without Java accounts)
sudo -u minecraft curl -L -o plugins/floodgate-spigot.jar https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot

# Download Paper (required for GeyserMC plugins)
cd /opt/minecraft
sudo -u minecraft curl -L -o paper.jar https://fill-data.papermc.io/v1/objects/c9dc93d44d0b0b414f7db9c746966c3991a33886c70fe04c403fd90381984088/paper-1.21.10-87.jar

# Create server directory structure
sudo -u minecraft mkdir -p /mnt/minecraft-data/world
sudo -u minecraft mkdir -p /mnt/minecraft-data/plugins

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

# Copy plugins to data directory (only if they don't exist)
if [ ! -f /mnt/minecraft-data/plugins/Geyser-Spigot.jar ]; then
  sudo -u minecraft cp /opt/minecraft/plugins/*.jar /mnt/minecraft-data/plugins/
fi

# Create GeyserMC config (only if it doesn't exist)
sudo -u minecraft mkdir -p /mnt/minecraft-data/plugins/Geyser-Spigot
if [ ! -f /mnt/minecraft-data/plugins/Geyser-Spigot/config.yml ]; then
  cat > /mnt/minecraft-data/plugins/Geyser-Spigot/config.yml <<GEYSEREOF
bedrock:
  port: 19132
  address: 0.0.0.0
remote:
  address: 127.0.0.1
  port: 25565
  auth-type: floodgate
GEYSEREOF
  chown minecraft:minecraft /mnt/minecraft-data/plugins/Geyser-Spigot/config.yml
fi

# Create graceful shutdown script
cat > /usr/local/bin/minecraft-stop.sh <<STOPEOF
#!/bin/bash
# Gracefully stop Minecraft server to prevent data corruption

# Send save-all command to ensure world is saved
if systemctl is-active --quiet minecraft.service; then
    echo "Saving Minecraft world..."
    # Use RCON or screen to send commands (using tmux/screen if available)
    # For now, send SIGTERM which Paper handles gracefully
    systemctl stop minecraft.service

    # Wait for server to fully stop (max 30 seconds)
    timeout=30
    while systemctl is-active --quiet minecraft.service && [ $timeout -gt 0 ]; do
        sleep 1
        timeout=$((timeout - 1))
    done

    if systemctl is-active --quiet minecraft.service; then
        echo "Server did not stop gracefully, forcing stop"
        systemctl kill minecraft.service
    else
        echo "Minecraft server stopped gracefully"
    fi
else
    echo "Minecraft server is not running"
fi
STOPEOF

chmod +x /usr/local/bin/minecraft-stop.sh

# Create systemd service with proper shutdown handling
cat > /etc/systemd/system/minecraft.service <<EOF
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=simple
User=minecraft
WorkingDirectory=/mnt/minecraft-data
ExecStart=/usr/bin/java -Xmx${server_memory} -Xms${server_memory} -jar /opt/minecraft/paper.jar nogui
ExecStop=/usr/local/bin/minecraft-stop.sh
TimeoutStopSec=60
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Minecraft server
systemctl daemon-reload
systemctl enable minecraft.service
systemctl start minecraft.service

# Install CloudWatch agent (optional but recommended)
dnf install -y amazon-cloudwatch-agent
