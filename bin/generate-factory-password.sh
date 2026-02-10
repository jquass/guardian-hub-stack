#!/bin/bash
# Run this ONCE when creating production image

FACTORY_PASSWORD_FILE="/opt/pi-stack/.factory-password"
SERIAL_FILE="/opt/pi-stack/.serial-number"
LABEL_OUTPUT_DIR="/opt/pi-stack/labels"
ENV_FILE="/opt/pi-stack/.env"

# Check if factory password already exists
if [ -f "$FACTORY_PASSWORD_FILE" ]; then
    echo "❌ Factory password already exists!"
    echo "This should only be run ONCE during production."
    echo "Delete existing files to regenerate (this will invalidate labels):"
    echo "  sudo rm $FACTORY_PASSWORD_FILE $SERIAL_FILE"
    exit 1
fi

# Generate cryptographically secure password
# Format: XXXX-XXXX-XXXX-XXXX (easy to read, easy to type)
PART1=$(openssl rand -hex 2 | tr '[:lower:]' '[:upper:]')
PART2=$(openssl rand -hex 2 | tr '[:lower:]' '[:upper:]')
PART3=$(openssl rand -hex 2 | tr '[:lower:]' '[:upper:]')
PART4=$(openssl rand -hex 2 | tr '[:lower:]' '[:upper:]')

FACTORY_PASSWORD="$PART1-$PART2-$PART3-$PART4"

# Generate serial number
SERIAL=$(date +%Y%m%d)-$(openssl rand -hex 3 | tr '[:lower:]' '[:upper:]')

# Hash the factory password using htpasswd (bcrypt)
FACTORY_PASSWORD_HASH=$(htpasswd -nbBC 10 "" "$FACTORY_PASSWORD" | cut -d: -f2)

# Hash the serial number
SERIAL_HASH=$(htpasswd -nbBC 10 "" "$SERIAL" | cut -d: -f2)

# Save hashed factory password (read-only)
echo "$FACTORY_PASSWORD_HASH" > "$FACTORY_PASSWORD_FILE"
chmod 400 "$FACTORY_PASSWORD_FILE"
chown admin:admin "$FACTORY_PASSWORD_FILE"

# Save hashed serial number (read-only)
echo "$SERIAL_HASH" > "$SERIAL_FILE"
chmod 400 "$SERIAL_FILE"
chown admin:admin "$SERIAL_FILE"

# Add LOGIN_PASSWORD to .env
if [ -f "$ENV_FILE" ]; then
    # Check if LOGIN_PASSWORD exists
    if grep -q "^LOGIN_PASSWORD=" "$ENV_FILE"; then
        # Update existing
        sed -i "s|^LOGIN_PASSWORD=.*|LOGIN_PASSWORD=$FACTORY_PASSWORD_HASH|" "$ENV_FILE"
    else
        # Add new entry at the end
        echo "" >> "$ENV_FILE"
        echo "# Device Login Password (bcrypt hash)" >> "$ENV_FILE"
        echo "LOGIN_PASSWORD=$FACTORY_PASSWORD_HASH" >> "$ENV_FILE"
    fi
    
    # Fix ownership and permissions
    chmod 600 "$ENV_FILE"
    chown admin:admin "$ENV_FILE"
    
    echo "✅ Added LOGIN_PASSWORD to .env"
else
    echo "⚠️  WARNING: .env file not found at $ENV_FILE"
    echo "Creating .env with LOGIN_PASSWORD..."
    
    cat > "$ENV_FILE" <<EOF
# Guardian Hub Configuration

# Device Login Password (bcrypt hash)
LOGIN_PASSWORD=$FACTORY_PASSWORD_HASH
EOF
    
    chmod 600 "$ENV_FILE"
    chown admin:admin "$ENV_FILE"
fi

# Create label directory
mkdir -p "$LABEL_OUTPUT_DIR"

# Generate printable label (HTML) - PLAIN TEXT VALUES
cat > "$LABEL_OUTPUT_DIR/label-$SERIAL.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Guardian Hub Label - $SERIAL</title>
    <style>
        @page {
            size: 2.5in 1.5in;
            margin: 0;
        }
        body {
            margin: 0;
            padding: 10px;
            font-family: 'Courier New', monospace;
            font-size: 11pt;
            width: 2.5in;
            height: 1.5in;
            box-sizing: border-box;
        }
        .header {
            font-weight: bold;
            font-size: 14pt;
            margin-bottom: 5px;
            text-align: center;
        }
        .password {
            font-size: 16pt;
            font-weight: bold;
            text-align: center;
            margin: 10px 0;
            letter-spacing: 1px;
            background: #f0f0f0;
            padding: 8px;
            border: 2px solid #333;
        }
        .info {
            font-size: 8pt;
            text-align: center;
            margin-top: 5px;
        }
        .serial {
            font-size: 7pt;
            text-align: center;
            color: #666;
            margin-top: 3px;
        }
    </style>
</head>
<body>
    <div class="header">🛡️ GUARDIAN HUB</div>
    <div class="password">$FACTORY_PASSWORD</div>
    <div class="info">Factory Password</div>
    <div class="info">config.guardian.home</div>
    <div class="serial">S/N: $SERIAL</div>
</body>
</html>
EOF

# Generate QR code version
cat > "$LABEL_OUTPUT_DIR/label-$SERIAL-qr.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Guardian Hub Label QR - $SERIAL</title>
    <script src="https://cdn.jsdelivr.net/npm/qrcode@1.5.3/build/qrcode.min.js"></script>
    <style>
        @page { size: 2.5in 1.5in; margin: 0; }
        body {
            margin: 0;
            padding: 5px;
            font-family: 'Courier New', monospace;
            text-align: center;
        }
        .header { font-weight: bold; font-size: 10pt; }
        #qrcode { margin: 5px auto; }
        .password { font-size: 12pt; font-weight: bold; margin-top: 5px; }
    </style>
</head>
<body>
    <div class="header">🛡️ GUARDIAN HUB</div>
    <div id="qrcode"></div>
    <div class="password">$FACTORY_PASSWORD</div>
    <script>
        QRCode.toCanvas(
            document.getElementById('qrcode'),
            '$FACTORY_PASSWORD',
            { width: 120, margin: 1 }
        );
    </script>
</body>
</html>
EOF

echo ""
echo "=========================================="
echo "✅ Factory Credentials Generated"
echo "=========================================="
echo ""
echo "⚠️  CREDENTIALS SHOWN BELOW - WRITE DOWN IMMEDIATELY"
echo ""
echo "  Password: $FACTORY_PASSWORD"
echo "  Serial:   $SERIAL"
echo ""
echo "📄 Label files created:"
echo "  - $LABEL_OUTPUT_DIR/label-$SERIAL.html"
echo "  - $LABEL_OUTPUT_DIR/label-$SERIAL-qr.html"
echo ""
echo "📋 Next Steps:"
echo "  1. WRITE DOWN credentials above (they won't be shown again)"
echo "  2. Open label HTML files in browser"
echo "  3. Print labels (2.5\" x 1.5\" label paper)"
echo "  4. Affix label to Guardian Hub device"
echo "  5. SECURELY DELETE label files after printing"
echo "  6. Create production SD card image"
echo ""
echo "⚠️  SECURITY NOTES:"
echo "  - Factory password and serial are HASHED in system files"
echo "  - Plain text values ONLY on printed label"
echo "  - DELETE label HTML files after printing!"
echo ""
echo "To securely delete label files:"
echo "  shred -zvu -n 5 $LABEL_OUTPUT_DIR/label-$SERIAL.html"
echo "  shred -zvu -n 5 $LABEL_OUTPUT_DIR/label-$SERIAL-qr.html"
echo ""
echo "=========================================="

# Clear variables
unset FACTORY_PASSWORD
unset SERIAL
unset FACTORY_PASSWORD_HASH
unset SERIAL_HASH
