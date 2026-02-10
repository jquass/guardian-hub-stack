#!/bin/bash

# Pi-hole Blocklist Auto-Configuration
# Uses FTL config to manage adlists

set -e

LOG_FILE="/var/log/guardian-hub-init.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Setting up Pi-hole blocklists..."

# Wait for Pi-hole to be ready
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
    log "WARNING: Pi-hole not ready after 30 seconds, skipping blocklist setup"
    exit 0
fi

# Define additional blocklists
BLOCKLISTS=(
    "https://big.oisd.nl"
    "https://o0.pages.dev/Lite/adblock.txt"
    "https://phishing.army/download/phishing_army_blocklist_extended.txt"
    "https://gitlab.com/malware-filter/urlhaus-filter/-/raw/master/urlhaus-filter-hosts.txt"
    "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt"
    "https://v.firebog.net/hosts/Easylist.txt"
    "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
)

# Build the blocklist array for FTL config
log "Configuring additional blocklists..."
ADLIST_CONFIG="["

# Add default list first
ADLIST_CONFIG+="\"https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts\","

# Add additional lists
for url in "${BLOCKLISTS[@]}"; do
    ADLIST_CONFIG+="\"$url\","
done

# Remove trailing comma and close array
ADLIST_CONFIG="${ADLIST_CONFIG%,}"
ADLIST_CONFIG+="]"

# Update FTL config
log "Updating Pi-hole adlist configuration..."
docker exec pihole pihole-FTL --config dns.adlists "$ADLIST_CONFIG" &>/dev/null

if [ $? -eq 0 ]; then
    log "✓ Adlists configured successfully"

    # Update gravity in background
    log "Updating gravity database..."
    docker exec pihole pihole updateGravity &>/dev/null &
    log "✅ Pi-hole blocklist setup complete (gravity updating in background)"
else
    log "✗ Failed to configure adlists"
    exit 1
fi
