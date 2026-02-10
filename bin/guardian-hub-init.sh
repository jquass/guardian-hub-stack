#!/bin/bash

# Guardian Hub Network Auto-Configuration
# Detects network settings and updates .env file only if changed

set -e

ENV_FILE="/opt/pi-stack/.env"
ENV_EXAMPLE="/opt/pi-stack/.env.example"
LOG_FILE="/var/log/guardian-hub-init.log"

# Create .env from template if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$ENV_EXAMPLE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] .env not found, creating from .env.example" | tee -a "$LOG_FILE"
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Created $ENV_FILE from template" | tee -a "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Neither .env nor .env.example found!" | tee -a "$LOG_FILE"
        exit 1
    fi
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# LED control functions
set_led_pattern() {
    local LED=$1      # ACT or PWR
    local PATTERN=$2  # none, heartbeat, default-on, timer, etc.

    echo "$PATTERN" | sudo tee /sys/class/leds/$LED/trigger > /dev/null 2>&1 || true
}

set_led_brightness() {
    local LED=$1
    local BRIGHTNESS=$2  # 0 (off) or 1 (on)

    echo "$BRIGHTNESS" | sudo tee /sys/class/leds/$LED/brightness > /dev/null 2>&1 || true
}

led_busy() {
    log "🔄 LED: Setting busy pattern..."
    set_led_pattern "ACT" "heartbeat"  # Green LED heartbeat = working
}

led_success() {
    log "✅ LED: Setting success pattern..."
    set_led_pattern "ACT" "none"       # Disable trigger
    set_led_brightness "ACT" 1         # Force on
}

led_error() {
    log "❌ LED: Setting error pattern..."
    set_led_pattern "ACT" "none"
    set_led_brightness "ACT" 0          # Turn off green
    set_led_pattern "PWR" "heartbeat"   # Red LED heartbeat = error
}

led_restore() {
    log "🔧 LED: Restoring default pattern..."
    set_led_pattern "ACT" "mmc0"        # Green LED back to SD activity
    set_led_pattern "PWR" "default-on"  # Red LED solid (default)
}

handle_error() {
    local ERROR_MSG=$1

    log "ERROR: $ERROR_MSG"
    led_error
    sleep 5
    led_restore
    exit 1
}

# Trap errors and restore LEDs before exiting
cleanup() {
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        log "❌ Script failed with exit code $EXIT_CODE"
        led_error
        sleep 5
    fi
    led_restore
    exit $EXIT_CODE
}

trap cleanup EXIT


log "========================================="
log "Guardian Hub Network Auto-Configuration"
log "========================================="

# Set busy LED pattern
led_busy

# Wait for network to be ready (max 60 seconds)
log "Waiting for network connection..."
for i in {1..60}; do
    if ping -c 1 -W 1 8.8.8.8 &> /dev/null; then
        log "Network is ready"
        break
    fi
    if [ $i -eq 60 ]; then
        log "ERROR: Network timeout after 60 seconds"
        exit 1
    fi
    sleep 1
done

# Get primary network interface (excluding docker, loopback, wireguard)
log "Detecting network interface..."
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$INTERFACE" ]; then
    handle_error "Could not detect network interface"
fi
log "Found interface: $INTERFACE"

# Get IP address
log "Detecting IP address..."
GUARDIAN_IP=$(ip -4 addr show "$INTERFACE" | grep -o 'inet [0-9.]*' | head -1 | awk '{print $2}' | cut -d'/' -f1)
if [ -z "$GUARDIAN_IP" ]; then
    handle_error "Could not detect IP address"
fi
log "Guardian IP: $GUARDIAN_IP"

# Get router IP (default gateway)
log "Detecting router IP..."
ROUTER_IP=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -z "$ROUTER_IP" ]; then
    handle_error "Could not detect router IP"
fi
log "Router IP: $ROUTER_IP"

# Calculate network CIDR from IP and netmask
log "Calculating network CIDR..."
NETMASK=$(ip -4 addr show "$INTERFACE" | grep inet | awk '{print $2}' | cut -d'/' -f2 | head -1)
NETWORK_BASE=$(echo "$GUARDIAN_IP" | awk -F. '{print $1"."$2"."$3".0"}')
NETWORK_CIDR="${NETWORK_BASE}/${NETMASK}"
log "Network CIDR: $NETWORK_CIDR"

# Detect network domain from DHCP/DNS
log "Detecting network domain..."
NETWORK_DOMAIN=$(grep -E "^search|^domain" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -1)
if [ -z "$NETWORK_DOMAIN" ]; then
    NETWORK_DOMAIN="local"
    log "No domain detected, using default: local"
else
    log "Detected domain: $NETWORK_DOMAIN"
fi

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    handle_error ".env file not found at $ENV_FILE"
fi

# Read current values from .env
log "Reading current configuration from .env..."
CURRENT_GUARDIAN_IP=$(grep "^GUARDIAN_IP=" "$ENV_FILE" | cut -d'=' -f2)
CURRENT_ROUTER_IP=$(grep "^ROUTER_IP=" "$ENV_FILE" | cut -d'=' -f2)
CURRENT_NETWORK_CIDR=$(grep "^NETWORK_CIDR=" "$ENV_FILE" | cut -d'=' -f2)
CURRENT_NETWORK_DOMAIN=$(grep "^NETWORK_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2)

log "Current configuration:"
log "  GUARDIAN_IP=$CURRENT_GUARDIAN_IP"
log "  ROUTER_IP=$CURRENT_ROUTER_IP"
log "  NETWORK_CIDR=$CURRENT_NETWORK_CIDR"
log "  NETWORK_DOMAIN=$CURRENT_NETWORK_DOMAIN"

# Check if anything changed
CHANGED=false

if [ "$CURRENT_GUARDIAN_IP" != "$GUARDIAN_IP" ]; then
    log "🔄 GUARDIAN_IP changed: $CURRENT_GUARDIAN_IP → $GUARDIAN_IP"
    CHANGED=true
fi

if [ "$CURRENT_ROUTER_IP" != "$ROUTER_IP" ]; then
    log "🔄 ROUTER_IP changed: $CURRENT_ROUTER_IP → $ROUTER_IP"
    CHANGED=true
fi

if [ "$CURRENT_NETWORK_CIDR" != "$NETWORK_CIDR" ]; then
    log "🔄 NETWORK_CIDR changed: $CURRENT_NETWORK_CIDR → $NETWORK_CIDR"
    CHANGED=true
fi

if [ "$CURRENT_NETWORK_DOMAIN" != "$NETWORK_DOMAIN" ]; then
    log "🔄 NETWORK_DOMAIN changed: $CURRENT_NETWORK_DOMAIN → $NETWORK_DOMAIN"
    CHANGED=true
fi

if [ "$CHANGED" = false ]; then
    log "✅ Network configuration unchanged"

    # Check if services are running
    cd /opt/pi-stack
    RUNNING=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)
    TOTAL=$(docker compose ps --services 2>/dev/null | wc -l)

    if [ "$RUNNING" -lt "$TOTAL" ]; then
        log "⚠️  Services not running ($RUNNING/$TOTAL), starting them..."
        docker compose up -d >> "$LOG_FILE" 2>&1
        sleep 15
    else
        log "✅ All services already running ($RUNNING/$TOTAL)"
    fi
fi

# Backup current .env
BACKUP_FILE="${ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
cp "$ENV_FILE" "$BACKUP_FILE"
log "Backed up .env to: $BACKUP_FILE"

# Update .env file (preserve passwords and TZ)
log "Updating .env file..."
sed -i "s|^GUARDIAN_IP=.*|GUARDIAN_IP=$GUARDIAN_IP|" "$ENV_FILE"
sed -i "s|^ROUTER_IP=.*|ROUTER_IP=$ROUTER_IP|" "$ENV_FILE"
sed -i "s|^NETWORK_CIDR=.*|NETWORK_CIDR=$NETWORK_CIDR|" "$ENV_FILE"
sed -i "s|^NETWORK_DOMAIN=.*|NETWORK_DOMAIN=$NETWORK_DOMAIN|" "$ENV_FILE"

log "Updated .env file with new values"

# Restart Guardian Hub with new configuration
log "Restarting Guardian Hub services..."
cd /opt/pi-stack

# Stop services
log "Stopping services..."
docker compose down >> "$LOG_FILE" 2>&1
log "Services stopped"

# Start services with updated configuration
log "Starting services with new configuration..."
docker compose up -d >> "$LOG_FILE" 2>&1
log "Services started"

# Wait for services to be healthy
log "Waiting for services to become healthy..."
sleep 15

# Check service status
RUNNING=$(docker compose ps --services --filter "status=running" | wc -l)
TOTAL=$(docker compose ps --services | wc -l)
log "Services running: $RUNNING/$TOTAL"

if [ "$RUNNING" -eq "$TOTAL" ]; then
    log "✅ All services are running"
else
    log "⚠️  Warning: Some services may not be running"
    docker compose ps >> "$LOG_FILE" 2>&1
fi

# =========================================
# Update Pi-hole DNS Records
# =========================================

log "Updating Pi-hole DNS records..."

# Wait for Pi-hole to be ready (up to 30 seconds)
PIHOLE_READY=false
for i in {1..30}; do
    if docker exec pihole pihole status &>/dev/null; then
        PIHOLE_READY=true
        log "Pi-hole is ready"
        break
    fi
    log "Waiting for Pi-hole to start... ($i/30)"
    sleep 1
done

if [ "$PIHOLE_READY" = false ]; then
    log "WARNING: Pi-hole not ready after 30 seconds, skipping DNS record update"
else
    # Define DNS records as array
    DNS_RECORDS="${GUARDIAN_IP} config.guardian.home homepage.guardian.home npm.guardian.home pihole.guardian.home wireguard.guardian.home"

    # Get current DNS hosts configuration
    CURRENT_DNS_HOSTS=$(docker exec pihole pihole-FTL --config dns.hosts 2>/dev/null || echo "")

    # Only update if changed
    if [[ "$CURRENT_DNS_HOSTS" == *"$DNS_RECORDS"* ]]; then
        log "DNS records already up to date"
    else
        log "Updating DNS records with IP: $GUARDIAN_IP"

	# Build DNS hosts array - each domain needs separate entry
	DNS_HOSTS_CONFIG="["
	DNS_HOSTS_CONFIG+="\"${GUARDIAN_IP} config.guardian.home\","
	DNS_HOSTS_CONFIG+="\"${GUARDIAN_IP} homepage.guardian.home\","
	DNS_HOSTS_CONFIG+="\"${GUARDIAN_IP} npm.guardian.home\","
	DNS_HOSTS_CONFIG+="\"${GUARDIAN_IP} pihole.guardian.home\","
	DNS_HOSTS_CONFIG+="\"${GUARDIAN_IP} wireguard.guardian.home\""
	DNS_HOSTS_CONFIG+="]"

	# Update DNS hosts configuration
	if docker exec pihole pihole-FTL --config dns.hosts "$DNS_HOSTS_CONFIG" &>/dev/null; then
	    log "DNS records configuration updated successfully"

	    # Reload Pi-hole to apply changes
	    if docker exec pihole pihole reloadlists &>/dev/null; then
	        log "Pi-hole DNS reloaded successfully"
	    else
	        log "WARNING: Failed to reload Pi-hole DNS"
	    fi
	else
	    log "WARNING: Failed to update DNS records configuration"
	fi
    fi
fi

# =========================================
# Update NPM Proxy Hosts
# =========================================

log "Configuring NPM proxy hosts..."
if /opt/pi-stack/bin/setup-npm.sh; then
    log "✅ NPM proxy hosts configured"
else
    log "⚠️  NPM proxy host configuration failed (see errors above)"
fi

# =========================================
# Success!
# =========================================

led_success

log "========================================="
log "✅ Network reconfiguration completed!"
log "========================================="

# Restore LEDs after 5 seconds
sleep 5
led_restore

exit 0
