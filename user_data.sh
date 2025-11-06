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

# Download latest Paper version
cd /opt/minecraft
MINECRAFT_VERSION="1.21.10"
LATEST_BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$MINECRAFT_VERSION" | sed 's/.*"builds":\[//;s/\].*//' | tr ',' '\n' | tail -1)
sudo -u minecraft curl -L -o paper.jar "https://api.papermc.io/v2/projects/paper/versions/$MINECRAFT_VERSION/builds/$LATEST_BUILD/downloads/paper-$MINECRAFT_VERSION-$LATEST_BUILD.jar"

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

# Create upgrade script for Paper and plugins
cat > /usr/local/bin/minecraft-upgrade.sh <<UPGRADEEOF
#!/bin/bash
# Upgrade Paper and all plugins to latest versions

echo "Starting Minecraft Paper and plugins upgrade..."

# Stop the server if running
if systemctl is-active --quiet minecraft.service; then
    echo "Stopping Minecraft server..."
    systemctl stop minecraft.service

    # Wait for server to stop
    timeout=30
    while systemctl is-active --quiet minecraft.service && [ \$timeout -gt 0 ]; do
        sleep 1
        timeout=\$((timeout - 1))
    done
fi

cd /opt/minecraft

# Backup current paper.jar
if [ -f paper.jar ]; then
    echo "Backing up current Paper jar..."
    cp paper.jar paper.jar.backup
fi

# Download latest Paper version
echo "Downloading latest Paper..."
MINECRAFT_VERSION="1.21.10"
LATEST_BUILD=\$(curl -s "https://api.papermc.io/v2/projects/paper/versions/\$MINECRAFT_VERSION" | sed 's/.*"builds":\[//;s/\].*//' | tr ',' '\n' | tail -1)
sudo -u minecraft curl -L -o paper.jar "https://api.papermc.io/v2/projects/paper/versions/\$MINECRAFT_VERSION/builds/\$LATEST_BUILD/downloads/paper-\$MINECRAFT_VERSION-\$LATEST_BUILD.jar"

echo "Paper upgraded successfully!"

# Backup and upgrade GeyserMC
if [ -f plugins/Geyser-Spigot.jar ]; then
    echo "Backing up and upgrading GeyserMC..."
    cp plugins/Geyser-Spigot.jar plugins/Geyser-Spigot.jar.backup
fi
sudo -u minecraft curl -L -o plugins/Geyser-Spigot.jar https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot

# Backup and upgrade Floodgate
if [ -f plugins/floodgate-spigot.jar ]; then
    echo "Backing up and upgrading Floodgate..."
    cp plugins/floodgate-spigot.jar plugins/floodgate-spigot.jar.backup
fi
sudo -u minecraft curl -L -o plugins/floodgate-spigot.jar https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot

# Copy upgraded plugins to data directory
echo "Copying upgraded plugins to data directory..."
sudo -u minecraft cp -f plugins/*.jar /mnt/minecraft-data/plugins/

echo "Upgrade complete! Starting Minecraft server..."
systemctl start minecraft.service

echo "Done! Monitor server startup with: sudo journalctl -u minecraft.service -f"
UPGRADEEOF

chmod +x /usr/local/bin/minecraft-upgrade.sh

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
ExecStart=/usr/bin/java -Xmx${server_memory} -Xms${server_memory} -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+ParallelRefProcEnabled -XX:+PerfDisableSharedMem -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1HeapRegionSize=8M -XX:G1HeapWastePercent=5 -XX:G1MaxNewSizePercent=40 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1NewSizePercent=30 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -XX:MaxGCPauseMillis=200 -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=32 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar /opt/minecraft/paper.jar nogui
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
