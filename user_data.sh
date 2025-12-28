#!/bin/bash
set -e

# Update system
dnf update -y

# Install and start SSM agent
dnf install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install Java 21 (required for Minecraft 1.20.1+)
dnf install -y java-21-amazon-corretto-headless

# Create minecraft user (only if it doesn't exist)
if ! id -u minecraft >/dev/null 2>&1; then
  useradd -m -r -s /bin/bash minecraft
fi

# Create minecraft directory
mkdir -p /opt/minecraft
chown minecraft:minecraft /opt/minecraft

# Mount EBS volume (only format if not already formatted)
if ! blkid /dev/nvme1n1 | grep -q ext4; then
  mkfs -t ext4 /dev/nvme1n1
fi
mkdir -p /mnt/minecraft-data
mount /dev/nvme1n1 /mnt/minecraft-data || mount -a

# Add to fstab for auto-mount on reboot (only if not already there)
UUID=$(blkid -s UUID -o value /dev/nvme1n1)
if ! grep -q "$UUID" /etc/fstab; then
  echo "UUID=$UUID /mnt/minecraft-data ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Set permissions
chown -R minecraft:minecraft /mnt/minecraft-data

# Cobblemon setup - using Fabric and Minecraft 1.20.1
cd /opt/minecraft

# Download Fabric server launcher
MINECRAFT_VERSION="1.21.1"
FABRIC_LOADER_VERSION="0.18.4"
FABRIC_INSTALLER_VERSION="1.1.0"

sudo -u minecraft curl -L -o fabric-installer.jar "https://meta.fabricmc.net/v2/versions/loader/$MINECRAFT_VERSION/$FABRIC_LOADER_VERSION/$FABRIC_INSTALLER_VERSION/server/jar"

# Create mods directory
sudo -u minecraft mkdir -p /mnt/minecraft-data/mods

# Download Fabric API (required dependency)
sudo -u minecraft curl -L -o /mnt/minecraft-data/mods/fabric-api.jar "https://cdn.modrinth.com/data/P7dR8mSH/versions/m6zu1K31/fabric-api-0.116.7%2B1.21.1.jar"

# Download Cobblemon
sudo -u minecraft curl -L -o /mnt/minecraft-data/mods/cobblemon.jar "https://cdn.modrinth.com/data/MdwFAVRL/versions/s64m1opn/Cobblemon-fabric-1.7.1%2B1.21.1.jar"

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

# Add admin user if specified
if [ -n "${admin_username}" ] && [ ! -f /mnt/minecraft-data/ops.json ]; then
  cat > /mnt/minecraft-data/ops.json <<EOF
[
  {
    "name": "${admin_username}",
    "level": 4,
    "bypassesPlayerLimit": true
  }
]
EOF
  chown minecraft:minecraft /mnt/minecraft-data/ops.json
fi

# Create upgrade script for Fabric and mods
cat > /usr/local/bin/minecraft-upgrade.sh <<'UPGRADEEOF'
#!/bin/bash
# Upgrade Fabric server and Cobblemon to latest versions

echo "Starting Minecraft Cobblemon upgrade..."

# Stop the server if running
if systemctl is-active --quiet minecraft.service; then
    echo "Stopping Minecraft server..."
    systemctl stop minecraft.service

    # Wait for server to stop
    timeout=30
    while systemctl is-active --quiet minecraft.service && [ $timeout -gt 0 ]; do
        sleep 1
        timeout=$((timeout - 1))
    done
fi

cd /opt/minecraft

# Backup current fabric-installer.jar
if [ -f fabric-installer.jar ]; then
    echo "Backing up current Fabric jar..."
    cp fabric-installer.jar fabric-installer.jar.backup
fi

# Download latest Fabric server launcher
echo "Downloading latest Fabric..."
MINECRAFT_VERSION="1.21.1"
FABRIC_LOADER_VERSION="0.18.4"
FABRIC_INSTALLER_VERSION="1.1.0"
sudo -u minecraft curl -L -o fabric-installer.jar "https://meta.fabricmc.net/v2/versions/loader/$MINECRAFT_VERSION/$FABRIC_LOADER_VERSION/$FABRIC_INSTALLER_VERSION/server/jar"

echo "Fabric upgraded successfully!"

# Backup and upgrade mods
echo "Backing up mods..."
if [ -d /mnt/minecraft-data/mods ]; then
    cp -r /mnt/minecraft-data/mods /mnt/minecraft-data/mods.backup.$(date +%Y%m%d_%H%M%S)
fi

echo "Upgrading Fabric API..."
sudo -u minecraft curl -L -o /mnt/minecraft-data/mods/fabric-api.jar "https://cdn.modrinth.com/data/P7dR8mSH/versions/m6zu1K31/fabric-api-0.116.7%2B1.21.1.jar"

echo "Upgrading Cobblemon..."
sudo -u minecraft curl -L -o /mnt/minecraft-data/mods/cobblemon.jar "https://cdn.modrinth.com/data/MdwFAVRL/versions/s64m1opn/Cobblemon-fabric-1.7.1%2B1.21.1.jar"

echo "Upgrade complete! Starting Minecraft server..."
systemctl start minecraft.service

echo "Done! Monitor server startup with: sudo journalctl -u minecraft.service -f"
UPGRADEEOF

chmod +x /usr/local/bin/minecraft-upgrade.sh

# Create graceful shutdown script
cat > /usr/local/bin/minecraft-stop.sh <<'STOPEOF'
#!/bin/bash
# Gracefully stop Minecraft server to prevent data corruption

# Send save-all command to ensure world is saved
if systemctl is-active --quiet minecraft.service; then
    echo "Saving Minecraft world..."
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
Description=Minecraft Cobblemon Server
After=network.target

[Service]
Type=simple
User=minecraft
WorkingDirectory=/mnt/minecraft-data
ExecStart=/usr/bin/java -Xmx${server_memory} -Xms${server_memory} -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+ParallelRefProcEnabled -XX:+PerfDisableSharedMem -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1HeapRegionSize=8M -XX:G1HeapWastePercent=5 -XX:G1MaxNewSizePercent=40 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1NewSizePercent=30 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -XX:MaxGCPauseMillis=200 -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=32 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar /opt/minecraft/fabric-installer.jar nogui
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
