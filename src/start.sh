#!/bin/bash
set -e

APP_DIR="/opt/tpm-attestation-app"
LOG_FILE="/var/log/tpm-attestation-app.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting TPM Attestation Application..."

# Wait for user data to be available
log "Waiting for user data..."
while [ ! -f /opt/user_data.json ]; do
    sleep 2
done

# Extract KMS key ID and encrypted symmetric key
KMS_KEY_ID=$(jq -r '.key_id' /opt/user_data.json)
ENCRYPTED_KEY=$(jq -r '.ciphertext' /opt/user_data.json)

log "Found KMS Key ID: $KMS_KEY_ID"

# Decrypt symmetric key using TPM attestation
log "Decrypting symmetric key using TPM attestation..."
# Base64 decode the encrypted key before passing to decrypt.sh
SYMMETRIC_KEY=$(echo "$ENCRYPTED_KEY" | base64 -d | "$APP_DIR/decrypt.sh" "$KMS_KEY_ID" -)

if [ -z "$SYMMETRIC_KEY" ]; then
    log "ERROR: Failed to decrypt symmetric key"
    exit 1
fi

# Store decrypted key for Flask application
echo "$SYMMETRIC_KEY" > /run/symmetric_key
chmod 600 /run/symmetric_key

log "Symmetric key decrypted and stored successfully"

# Start Flask application
log "Starting Flask application on port 80..."
cd "$APP_DIR"
exec python3 app.py
