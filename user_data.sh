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

# Install mcrcon for RCON communication
dnf install -y git gcc make
cd /tmp
git clone https://github.com/Tiiffi/mcrcon.git
cd mcrcon
make
make install
cd /
rm -rf /tmp/mcrcon

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

# Create idle monitor script
cat > /usr/local/bin/minecraft-idle-monitor.sh <<'IDLEOF'
#!/bin/bash
# Monitor Minecraft server for idle players and auto-stop after 1 hour

IDLE_FILE="/var/lib/minecraft/idle_since"
IDLE_THRESHOLD=${idle_timeout_seconds}  # Configurable idle timeout in seconds
AWS_REGION="${aws_region}"
SNS_TOPIC_ARN="${sns_topic_arn}"

# Function to get player count using RCON
# Returns: player count (0+), -1 if server is down, -2 if RCON fails
get_player_count() {
    # Check if server is running
    if ! systemctl is-active --quiet minecraft.service; then
        echo "-1"
        return
    fi

    # Use mcrcon to get player list
    # The "list" command returns something like: "There are 0 of a max of 20 players online:"
    RCON_OUTPUT=$(mcrcon -H localhost -P 25575 -p "${rcon_password}" "list" 2>/dev/null)

    if [ $? -eq 0 ]; then
        # Extract player count from output
        # Format: "There are X of a max of Y players online:"
        PLAYER_COUNT=$(echo "$RCON_OUTPUT" | grep -oP 'There are \K[0-9]+' || echo "0")
        echo "$PLAYER_COUNT"
    else
        # RCON connection failed
        echo "-2"
    fi
}

# Get current player count
PLAYER_COUNT=$(get_player_count)

# Handle server down or RCON failure
if [ "$PLAYER_COUNT" = "-1" ] || [ "$PLAYER_COUNT" = "-2" ]; then
    # Check if we already have an idle file tracking this failure
    if [ ! -f "$IDLE_FILE" ]; then
        # First time seeing this failure - create idle file with timestamp
        date +%s > "$IDLE_FILE"
        exit 0
    fi

    # Read idle start time
    IDLE_START=$(cat "$IDLE_FILE")
    CURRENT_TIME=$(date +%s)
    IDLE_DURATION=$((CURRENT_TIME - IDLE_START))

    # Check if failure has persisted for threshold
    if [ $IDLE_DURATION -ge $IDLE_THRESHOLD ]; then
        echo "Server unreachable for $IDLE_DURATION seconds. Stopping instance..."

        # Get instance ID
        INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)

        # Determine failure reason
        if [ "$PLAYER_COUNT" = "-1" ]; then
            FAILURE_REASON="Minecraft server service is not running"
        else
            FAILURE_REASON="RCON connection failed (server may be unresponsive or crashed)"
        fi

        # Send SNS notification if configured
        if [ -n "$SNS_TOPIC_ARN" ]; then
            aws sns publish \
                --region "$AWS_REGION" \
                --topic-arn "$SNS_TOPIC_ARN" \
                --subject "Minecraft Server Auto-Stopping - Server Unreachable" \
                --message "Minecraft server has been unreachable for 1 hour. Reason: $FAILURE_REASON. Automatically stopping instance $INSTANCE_ID to save costs." \
                2>/dev/null || true
        fi

        # Stop the instance
        aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" 2>/dev/null || true

        # Clean up idle file (may not complete if instance stops too quickly)
        # Note: This is a best-effort cleanup. The minecraft-idle-cleanup.service
        # runs on every boot to clear this file and prevent stale timestamps
        rm -f "$IDLE_FILE"
    fi

    exit 0
fi

# If players are online, remove idle file and exit
if [ "$PLAYER_COUNT" -gt 0 ]; then
    rm -f "$IDLE_FILE"
    exit 0
fi

# No players online - check idle time
if [ ! -f "$IDLE_FILE" ]; then
    # First time seeing zero players - create idle file with timestamp
    date +%s > "$IDLE_FILE"
    exit 0
fi

# Read idle start time
IDLE_START=$(cat "$IDLE_FILE")
CURRENT_TIME=$(date +%s)
IDLE_DURATION=$((CURRENT_TIME - IDLE_START))

# Check if idle threshold exceeded
if [ $IDLE_DURATION -ge $IDLE_THRESHOLD ]; then
    echo "Server idle for $IDLE_DURATION seconds. Stopping instance..."

    # Get instance ID
    INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)

    # Send SNS notification if configured
    if [ -n "$SNS_TOPIC_ARN" ]; then
        aws sns publish \
            --region "$AWS_REGION" \
            --topic-arn "$SNS_TOPIC_ARN" \
            --subject "Minecraft Server Auto-Stopping" \
            --message "Minecraft server has been idle for 1 hour with no players online. Automatically stopping instance $INSTANCE_ID." \
            2>/dev/null || true
    fi

    # Stop the instance
    aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" 2>/dev/null || true

    # Clean up idle file (may not complete if instance stops too quickly)
    # Note: This is a best-effort cleanup. The minecraft-idle-cleanup.service
    # runs on every boot to clear this file and prevent stale timestamps
    rm -f "$IDLE_FILE"
fi
IDLEOF

chmod +x /usr/local/bin/minecraft-idle-monitor.sh

# Create idle state directory
mkdir -p /var/lib/minecraft
chown minecraft:minecraft /var/lib/minecraft

# Create a systemd service to clean up stale idle file on every boot
# This prevents inheriting old timestamps from previous runs if instance was manually stopped/started
cat > /etc/systemd/system/minecraft-idle-cleanup.service <<'CLEANUPEOF'
[Unit]
Description=Clean up Minecraft idle tracking file on boot
Before=minecraft.service
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/rm -f /var/lib/minecraft/idle_since
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
CLEANUPEOF

systemctl enable minecraft-idle-cleanup.service

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

# Setup cron job for idle monitoring (runs every 10 minutes)
cat > /etc/cron.d/minecraft-idle-monitor <<CRONEOF
*/10 * * * * root /usr/local/bin/minecraft-idle-monitor.sh >> /var/log/minecraft-idle-monitor.log 2>&1
CRONEOF

chmod 644 /etc/cron.d/minecraft-idle-monitor
