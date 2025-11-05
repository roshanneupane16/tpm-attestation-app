#!/bin/bash

# EC2 Instance Launcher Script
# Usage: ./launch-ec2-instance.sh <AMI_ID> [delete]

set -e

STACK_NAME="zoa-tpm-enabled-instance"
CFN_TEMPLATE="static/cfn/launch-ec2.yaml"

# Default values
USER_DATA_FILE=""
ASSOCIATE_PUBLIC_IP="true"

# Function to display usage
usage() {
    echo "Usage: $0 <AMI_ID> [options]"
    echo ""
    echo "Arguments:"
    echo "  AMI_ID    - The AMI ID to launch (required)"
    echo ""
    echo "Options:"
    echo "  --user-data <file>  - Path to user data script file"
    echo "  --no-public-ip      - Do not associate a public IP address"
    echo "  delete              - Delete the CloudFormation stack"
    echo ""
    echo "Examples:"
    echo "  $0 ami-0abcdef1234567890"
    echo "  $0 ami-0abcdef1234567890 --user-data user_data.sh"
    echo "  $0 ami-0abcdef1234567890 --no-public-ip"
    echo "  $0 ami-0abcdef1234567890 --user-data user_data.sh --no-public-ip"
    echo "  $0 delete"
    exit 1
}

# Function to encode user data
encode_user_data() {
    local file_path=$1
    if [ -n "$file_path" ] && [ -f "$file_path" ]; then
        base64 -i "$file_path" | tr -d '\n'
    else
        echo ""
    fi
}

# Function to get current instance metadata
get_current_instance_info() {
    echo "Getting current instance information..."
    
    # Get IMDSv2 token
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
    
    if [ -z "$TOKEN" ]; then
        echo "Error: Could not retrieve IMDSv2 token. Are you running this on an EC2 instance?"
        exit 1
    fi
    
    # Get current instance info
    CURRENT_INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
        -s http://169.254.169.254/latest/meta-data/instance-id)
    
    CURRENT_INSTANCE_TYPE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
        -s http://169.254.169.254/latest/meta-data/instance-type)
    
    echo "Current Instance ID: $CURRENT_INSTANCE_ID"
    echo "Current Instance Type: $CURRENT_INSTANCE_TYPE"
    
    # Get VPC and subnet info from AWS CLI
    INSTANCE_INFO=$(aws ec2 describe-instances --instance-ids $CURRENT_INSTANCE_ID \
        --query 'Reservations[0].Instances[0]' --output json)
    
    VPC_ID=$(echo $INSTANCE_INFO | jq -r '.VpcId')
    SUBNET_ID=$(echo $INSTANCE_INFO | jq -r '.SubnetId')
    CURRENT_PRIVATE_IP=$(echo $INSTANCE_INFO | jq -r '.PrivateIpAddress')
    
    echo "VPC ID: $VPC_ID"
    echo "Subnet ID: $SUBNET_ID"
    echo "Current Private IP: $CURRENT_PRIVATE_IP"
}

# Function to delete CloudFormation stack
delete_stack() {
    echo "Deleting CloudFormation stack: $STACK_NAME"
    
    if aws cloudformation describe-stacks --stack-name $STACK_NAME >/dev/null 2>&1; then
        aws cloudformation delete-stack --stack-name $STACK_NAME
        echo "Waiting for stack deletion to complete..."
        aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME
        echo "Stack deleted successfully!"
    else
        echo "Stack $STACK_NAME does not exist or has already been deleted."
    fi
}

# Function to create CloudFormation stack
create_stack() {
    local ami_id=$1
    
    echo "Creating CloudFormation stack: $STACK_NAME"
    echo "Using AMI: $ami_id"
    echo "Associate Public IP: $ASSOCIATE_PUBLIC_IP"
    if [ -n "$USER_DATA_FILE" ]; then
        echo "User Data File: $USER_DATA_FILE"
    fi
    
    # Check if template exists
    if [ ! -f "$CFN_TEMPLATE" ]; then
        echo "Error: CloudFormation template not found at $CFN_TEMPLATE"
        exit 1
    fi
    
    # Encode user data if provided
    USER_DATA_ENCODED=$(encode_user_data "$USER_DATA_FILE")
    
    # Create or update stack
    if aws cloudformation describe-stacks --stack-name $STACK_NAME >/dev/null 2>&1; then
        echo "Stack exists, updating..."
        aws cloudformation update-stack \
            --stack-name $STACK_NAME \
            --template-body file://$CFN_TEMPLATE \
            --parameters \
                ParameterKey=AMIId,ParameterValue=$ami_id \
                ParameterKey=InstanceType,ParameterValue=$CURRENT_INSTANCE_TYPE \
                ParameterKey=VpcId,ParameterValue=$VPC_ID \
                ParameterKey=SubnetId,ParameterValue=$SUBNET_ID \
                ParameterKey=CurrentInstancePrivateIP,ParameterValue=$CURRENT_PRIVATE_IP \
                ParameterKey=InstanceName,ParameterValue="LaunchedInstance-$(date +%Y%m%d-%H%M%S)" \
                ParameterKey=InstanceProfileName,ParameterValue="TPMAttestationProfile" \
                ParameterKey=AssociatePublicIpAddress,ParameterValue="$ASSOCIATE_PUBLIC_IP" \
                ParameterKey=UserData,ParameterValue="$USER_DATA_ENCODED" \
            --capabilities CAPABILITY_IAM
        
        echo "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete --stack-name $STACK_NAME
    else
        echo "Creating new stack..."
        aws cloudformation create-stack \
            --stack-name $STACK_NAME \
            --template-body file://$CFN_TEMPLATE \
            --parameters \
                ParameterKey=AMIId,ParameterValue=$ami_id \
                ParameterKey=InstanceType,ParameterValue=$CURRENT_INSTANCE_TYPE \
                ParameterKey=VpcId,ParameterValue=$VPC_ID \
                ParameterKey=SubnetId,ParameterValue=$SUBNET_ID \
                ParameterKey=CurrentInstancePrivateIP,ParameterValue=$CURRENT_PRIVATE_IP \
                ParameterKey=InstanceName,ParameterValue="LaunchedInstance-$(date +%Y%m%d-%H%M%S)" \
                ParameterKey=InstanceProfileName,ParameterValue="TPMAttestationProfile" \
                ParameterKey=AssociatePublicIpAddress,ParameterValue="$ASSOCIATE_PUBLIC_IP" \
                ParameterKey=UserData,ParameterValue="$USER_DATA_ENCODED" \
            --capabilities CAPABILITY_IAM
        
        echo "Waiting for stack creation to complete..."
        aws cloudformation wait stack-create-complete --stack-name $STACK_NAME
    fi
    
    echo "Stack operation completed successfully!"
    
    # Get outputs
    echo ""
    echo "Stack Outputs:"
    aws cloudformation describe-stacks --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table
}

# Main script logic
main() {
    # Check arguments
    if [ $# -eq 0 ]; then
        usage
    fi
    
    # Check if delete operation
    if [ "$1" = "delete" ]; then
        delete_stack
        exit 0
    fi
    
    AMI_ID=$1
    shift
    
    # Parse options
    while [ $# -gt 0 ]; do
        case $1 in
            --user-data)
                if [ -z "$2" ]; then
                    echo "Error: --user-data requires a file path"
                    exit 1
                fi
                USER_DATA_FILE="$2"
                if [ ! -f "$USER_DATA_FILE" ]; then
                    echo "Error: User data file not found: $USER_DATA_FILE"
                    exit 1
                fi
                shift 2
                ;;
            --no-public-ip)
                ASSOCIATE_PUBLIC_IP="false"
                shift
                ;;
            delete)
                delete_stack
                exit 0
                ;;
            *)
                echo "Error: Unknown option $1"
                usage
                ;;
        esac
    done
    
    # Validate AMI ID format
    if [[ ! $AMI_ID =~ ^ami-[0-9a-f]{8,17}$ ]]; then
        echo "Error: Invalid AMI ID format. Expected format: ami-xxxxxxxxx"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required but not installed. Please install jq first."
        exit 1
    fi
    
    # Get current instance information
    get_current_instance_info
    
    # Create the stack
    create_stack $AMI_ID
    
    echo ""
    echo "Instance launched successfully!"
    echo "To delete the instance, run: $0 delete"
}

# Run main function
main "$@"