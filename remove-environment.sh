#!/usr/bin/env bash

# set -x
# set -e

source variables.sh

# Remove instances
VPC_ID="$(aws ec2 describe-vpcs --filter "Name=tag:Project,Values=$PROJECT" "Name=tag:Environment,Values=$ENVIRONMENT" "Name=tag:Creator,Values=$CREATOR" --query "Vpcs[].VpcId" --output text)"

instances="$(aws ec2 describe-instances --filter "Name=instance-state-name,Values=running" "Name=vpc-id,Values=$VPC_ID" --query "Reservations[].Instances[].[InstanceId]" --output text)"
aws ec2 terminate-instances --instance-ids $instances
aws ec2 wait instance-terminated --instance-ids $instances

# Remove kay pair
aws ec2 delete-key-pair --key-name "$PROJECT-$ENVIRONMENT-$CREATOR"

# Remove igw
IGW_ID="$(aws ec2 describe-internet-gateways --filter "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[].InternetGatewayId" --output text)"
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"

# Remove subnets
SUBNETS="$(aws ec2 describe-subnets --filter "Name=vpc-id,Values=$VPC_ID" --query "Subnets[].SubnetId" --output text)"
for subnet in $SUBNETS; do
    aws ec2 delete-subnet --subnet-id "$subnet"
done

# Remove sg
SGS_ID="$(aws ec2 describe-security-groups --filter "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[].GroupId" --output text)"
for sg in $SGS_ID; do
    aws ec2 delete-security-group --group-id $sg
done

# Remove vpc
aws ec2 delete-vpc --vpc-id "$VPC_ID"

# Remove eip
ALLOCATION_ID="$(aws ec2 describe-addresses --filter "Name=tag:Project,Values=$PROJECT" "Name=tag:Environment,Values=$ENVIRONMENT" "Name=tag:Creator,Values=$CREATOR" --query "Addresses[].AllocationId" --output text)"
aws ec2 release-address --allocation-id "$ALLOCATION_ID"
