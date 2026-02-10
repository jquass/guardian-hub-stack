#!/bin/bash

# NPM Proxy Host Auto-Configuration
# Creates Guardian Hub proxy hosts via NPM API

set -e

LOG_FILE="/var/log/guardian-hub-init.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get Guardian IP from .env
GUARDIAN_IP=$(grep "^GUARDIAN_IP=" /opt/pi-stack/.env | cut -d'=' -f2)

if [ -z "$GUARDIAN_IP" ]; then
    log "ERROR: GUARDIAN_IP not found in .env"
    exit 1
fi

log "Setting up NPM proxy hosts for IP: $GUARDIAN_IP"

# Load credentials from .env
NPM_EMAIL=$(grep "^NPM_ADMIN_EMAIL=" /opt/pi-stack/.env | cut -d'=' -f2)
NPM_PASSWORD=$(grep "^NPM_ADMIN_PASSWORD=" /opt/pi-stack/.env | cut -d'=' -f2)

if [ -z "$NPM_EMAIL" ] || [ -z "$NPM_PASSWORD" ]; then
    log "ERROR: NPM credentials not found in .env"
    log "Please add NPM_ADMIN_EMAIL and NPM_ADMIN_PASSWORD to .env"
    exit 1
fi

# Wait for NPM to be ready
NPM_READY=false
for i in {1..30}; do
    if curl -s http://172.20.0.5:81 >/dev/null 2>&1; then
        NPM_READY=true
        log "NPM is ready"
        break
    fi
    log "Waiting for NPM to start... ($i/30)"
    sleep 1
done

if [ "$NPM_READY" = false ]; then
    log "WARNING: NPM not ready after 30 seconds, skipping proxy host setup"
    exit 0
fi

# Get API token
log "Authenticating with NPM API..."
TOKEN=$(curl -s -X POST http://172.20.0.5:81/api/tokens \
    -H "Content-Type: application/json" \
    -d "{
        \"identity\": \"$NPM_EMAIL\",
        \"secret\": \"$NPM_PASSWORD\"
    }" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    log "WARNING: Failed to authenticate with NPM"
    log "Check NPM_ADMIN_EMAIL and NPM_ADMIN_PASSWORD in .env"
    exit 0
fi

log "Authentication successful"

# Function to create proxy host (idempotent - checks if exists first)
create_proxy_host() {
    local DOMAIN=$1
    local CONTAINER_IP=$2
    local CONTAINER_PORT=$3
    
    # Check if host already exists
    EXISTING=$(curl -s -X GET "http://172.20.0.5:81/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $TOKEN" | grep -c "\"$DOMAIN\"" || true)
    
    if [ "$EXISTING" -gt 0 ]; then
        log "  ✓ $DOMAIN already exists"
        return 0
    fi
    
    # Create proxy host
    log "  Creating $DOMAIN..."
    RESPONSE=$(curl -s -X POST http://172.20.0.5:81/api/nginx/proxy-hosts \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\": [\"$DOMAIN\"],
            \"forward_scheme\": \"http\",
            \"forward_host\": \"$CONTAINER_IP\",
            \"forward_port\": $CONTAINER_PORT,
            \"access_list_id\": 0,
            \"certificate_id\": 0,
            \"ssl_forced\": false,
            \"caching_enabled\": false,
            \"block_exploits\": true,
            \"advanced_config\": \"\",
            \"meta\": {},
            \"allow_websocket_upgrade\": true,
            \"http2_support\": true,
            \"hsts_enabled\": false,
            \"hsts_subdomains\": false
        }")
    
    if echo "$RESPONSE" | grep -q "\"id\""; then
        log "  ✓ Created $DOMAIN successfully"
    else
        log "  ✗ Failed to create $DOMAIN"
    fi
}

# Create all Guardian Hub proxy hosts
log "Creating proxy hosts..."

create_proxy_host "config.guardian.home" "172.20.0.11" "8888"
create_proxy_host "pihole.guardian.home" "172.20.0.3" "80"
create_proxy_host "wireguard.guardian.home" "172.20.0.4" "51821"
create_proxy_host "npm.guardian.home" "172.20.0.5" "81"
create_proxy_host "homepage.guardian.home" "172.20.0.10" "3000"
create_proxy_host "$GUARDIAN_IP" "172.20.0.11" "8888"

log "✅ NPM proxy host setup complete"
