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

# Minecraft server setup
cd /opt/minecraft
MINECRAFT_VERSION="${minecraft_version}"
SERVER_TYPE="${server_type}"

# Setup based on server type
if [ "$SERVER_TYPE" = "fabric" ]; then
  echo "Setting up Fabric server..."
  FABRIC_LOADER_VERSION="${fabric_loader_version}"
  FABRIC_INSTALLER_VERSION="${fabric_installer_version}"

  sudo -u minecraft curl -L -o server.jar "https://meta.fabricmc.net/v2/versions/loader/$MINECRAFT_VERSION/$FABRIC_LOADER_VERSION/$FABRIC_INSTALLER_VERSION/server/jar"

  # Create mods directory
  sudo -u minecraft mkdir -p /mnt/minecraft-data/mods

  # Download mods if specified
  MOD_URLS="${mod_urls}"
  if [ -n "$MOD_URLS" ]; then
    IFS=',' read -ra MODS <<< "$MOD_URLS"
    for mod_url in "$${MODS[@]}"; do
      if [ -n "$mod_url" ]; then
        mod_filename=$(basename "$mod_url")
        echo "Downloading mod: $mod_filename"
        sudo -u minecraft curl -L -o "/mnt/minecraft-data/mods/$mod_filename" "$mod_url"
      fi
    done
  fi

elif [ "$SERVER_TYPE" = "paper" ]; then
  echo "Setting up Paper server..."
  SERVER_JAR_URL="${server_jar_url}"

  if [ -n "$SERVER_JAR_URL" ]; then
    sudo -u minecraft curl -L -o server.jar "$SERVER_JAR_URL"
  else
    # Download latest Paper if no URL provided
    echo "Downloading latest Paper..."
    BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$MINECRAFT_VERSION" | grep -o '"builds":\[[0-9]*\]' | grep -o '[0-9]*' | tail -1)
    sudo -u minecraft curl -L -o server.jar "https://api.papermc.io/v2/projects/paper/versions/$MINECRAFT_VERSION/builds/$BUILD/downloads/paper-$MINECRAFT_VERSION-$BUILD.jar"
  fi

  # Create plugins directory
  sudo -u minecraft mkdir -p /mnt/minecraft-data/plugins

  # Download plugins if specified
  PLUGIN_URLS="${plugin_urls}"
  if [ -n "$PLUGIN_URLS" ]; then
    IFS=',' read -ra PLUGINS <<< "$PLUGIN_URLS"
    for plugin_url in "$${PLUGINS[@]}"; do
      if [ -n "$plugin_url" ]; then
        plugin_filename=$(basename "$plugin_url")
        echo "Downloading plugin: $plugin_filename"
        sudo -u minecraft curl -L -o "/mnt/minecraft-data/plugins/$plugin_filename" "$plugin_url"
      fi
    done
  fi

else
  echo "Setting up Vanilla server..."
  SERVER_JAR_URL="${server_jar_url}"

  if [ -n "$SERVER_JAR_URL" ]; then
    sudo -u minecraft curl -L -o server.jar "$SERVER_JAR_URL"
  else
    # Download vanilla server from Mojang
    echo "Downloading vanilla Minecraft server $MINECRAFT_VERSION..."
    MANIFEST=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json)
    VERSION_URL=$(echo "$MANIFEST" | grep -o "\"url\":\"[^\"]*\"" | grep "$MINECRAFT_VERSION" | head -1 | cut -d'"' -f4)
    SERVER_URL=$(curl -s "$VERSION_URL" | grep -o "\"server\":{\"sha1\":\"[^\"]*\",\"size\":[0-9]*,\"url\":\"[^\"]*\"" | cut -d'"' -f12)
    sudo -u minecraft curl -L -o server.jar "$SERVER_URL"
  fi
fi

# Download datapacks if specified
DATAPACK_URLS="${datapack_urls}"
if [ -n "$DATAPACK_URLS" ]; then
  # Create world directory if it doesn't exist yet (server will use it)
  sudo -u minecraft mkdir -p /mnt/minecraft-data/world/datapacks

  IFS=',' read -ra DATAPACKS <<< "$DATAPACK_URLS"
  for datapack_url in "$${DATAPACKS[@]}"; do
    if [ -n "$datapack_url" ]; then
      datapack_filename=$(basename "$datapack_url")
      echo "Downloading datapack: $datapack_filename"
      sudo -u minecraft curl -L -o "/mnt/minecraft-data/world/datapacks/$datapack_filename" "$datapack_url"
    fi
  done
fi

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
if [ -n "${admin_username}" ] && [ -n "${admin_uuid}" ] && [ ! -f /mnt/minecraft-data/ops.json ]; then
  cat > /mnt/minecraft-data/ops.json <<EOF
[
  {
    "uuid": "${admin_uuid}",
    "name": "${admin_username}",
    "level": 4,
    "bypassesPlayerLimit": true
  }
]
EOF
  chown minecraft:minecraft /mnt/minecraft-data/ops.json
fi

# Note: Upgrade script removed - use terraform apply with new versions to upgrade

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
Description=Minecraft Server (${server_type})
After=network.target

[Service]
Type=simple
User=minecraft
WorkingDirectory=/mnt/minecraft-data
ExecStart=/usr/bin/java -Xmx${server_memory} -Xms${server_memory} -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+ParallelRefProcEnabled -XX:+PerfDisableSharedMem -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1HeapRegionSize=8M -XX:G1HeapWastePercent=5 -XX:G1MaxNewSizePercent=40 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1NewSizePercent=30 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -XX:MaxGCPauseMillis=200 -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=32 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar /opt/minecraft/server.jar nogui
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
