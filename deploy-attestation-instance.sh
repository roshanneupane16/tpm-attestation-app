#!/bin/bash
set -e

# Configuration
INSTANCE_TYPE="m5n.large"
KEY_PAIR_NAME="mobile"

# Get current instance metadata
CURRENT_SUBNET_ID=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=availability-zone,Values=${CURRENT_SUBNET_ID}a" --query 'Subnets[0].SubnetId' --output text)
SECURITY_GROUP_ID=$(curl -s http://169.254.169.254/latest/meta-data/security-groups)

# Check required variables
if [ -z "$AMI_ID" ] || [ -z "$KMS_KEY_ID" ]; then
    echo "Error: Required variables not set"
    echo "Please set: AMI_ID, KMS_KEY_ID"
    echo "Example:"
    echo "  export AMI_ID=ami-xxxxxxxxx"
    echo "  export KMS_KEY_ID=arn:aws:kms:region:account:key/key-id"
    exit 1
fi

echo "Deploying attestation instance..."
echo "AMI ID: $AMI_ID"
echo "KMS Key ID: $KMS_KEY_ID"

# Create encrypted symmetric key for testing
echo "Creating test symmetric key..."
SYMMETRIC_KEY=$(openssl rand -base64 32)
echo "Test data to encrypt" | openssl enc -aes-256-cbc -base64 -K $(echo "$SYMMETRIC_KEY" | base64 -d | xxd -p -c 256) -iv $(openssl rand -hex 16) > test_encrypted.txt

# Encrypt symmetric key with KMS
echo "Encrypting symmetric key with KMS..."
ENCRYPTED_KEY=$(echo "$SYMMETRIC_KEY" | aws kms encrypt \
    --key-id "$KMS_KEY_ID" \
    --plaintext fileb:///dev/stdin \
    --query 'CiphertextBlob' --output text)

# Create user data JSON
cat > user_data.json << EOF
{
  "key_id": "$KMS_KEY_ID",
  "ciphertext": "$ENCRYPTED_KEY"
}
EOF

# Create cloud-init script to save user data
cat > cloud_init.sh << 'EOF'
#!/bin/bash
# Get user data and save to expected location
curl -s http://169.254.169.254/latest/user-data > /opt/user_data.json
chmod 600 /opt/user_data.json
EOF

# Launch EC2 instance
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_PAIR_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --user-data file://user_data.json \
    --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=2,HttpEndpoint=enabled" \
    --query 'Instances[0].InstanceId' --output text)

if [ -n "$INSTANCE_ID" ]; then
    echo "✓ Instance launched: $INSTANCE_ID"
    
    # Wait for instance to be running
    echo "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    
    # Get public IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    
    echo "✓ Instance is running"
    echo "✓ Public IP: $PUBLIC_IP"
    echo ""
    echo "Test the attestation application:"
    echo "  Health check: curl http://$PUBLIC_IP/health"
    echo "  Decrypt test: curl \"http://$PUBLIC_IP/?ciphertext=\$(cat test_encrypted.txt)\""
    
    # Save instance details
    echo "export INSTANCE_ID=$INSTANCE_ID" >> ~/.bashrc
    echo "export PUBLIC_IP=$PUBLIC_IP" >> ~/.bashrc
    
else
    echo "✗ Failed to launch instance"
    exit 1
fi
