#!/usr/bin/env bash

# set -x
# set -e

source variables.sh

# Create VPC
VPC_ID="$(aws ec2 create-vpc --cidr-block $CIDR_BLOCK --query 'Vpc.VpcId' --output text)"
aws ec2 modify-vpc-attribute --enable-dns-hostnames --vpc-id "$VPC_ID"

# Create subnets
SUBNET_A_ID="$(aws ec2 create-subnet --availability-zone "$AZ_A" --cidr-block "$SUBNET_A" --vpc-id "$VPC_ID" --query 'Subnet.SubnetId' --output text)"
SUBNET_B_ID="$(aws ec2 create-subnet --availability-zone "$AZ_B" --cidr-block "$SUBNET_B" --vpc-id "$VPC_ID" --query 'Subnet.SubnetId' --output text)"

for subnet in $SUBNET_A_ID $SUBNET_B_ID;
do
    aws ec2 modify-subnet-attribute --map-public-ip-on-launch --subnet-id "$subnet"
done

# Create Internet Gateway
IGW_ID="$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)"

# Attach Internet Gateway to VPC
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

# Add routes
ROUTING_TABLE_ID="$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[].RouteTableId' --output text)"
aws ec2 create-route --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --route-table-id "$ROUTING_TABLE_ID"

# Create security group
SG_ID="$(aws ec2 create-security-group --group-name "$SG_NAME" --description "$SG_DESCRIPTION" --vpc-id "$VPC_ID" --output text)"

# Add tags to the created security group
# aws ec2 create-tags --resources "$SG_ID" --tags Key=Project,Value="${project_name}" Key=Environment,Value="${environment}" Key=Creator,Value="${creator}"

# Rule - Allow ping to the servers
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --ip-permissions '[{"IpProtocol": "icmp", "FromPort": -1, "ToPort": -1, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow ping from any"}]}]'
# Rule - Allow SSH from any
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --ip-permissions '[{"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow SSH from any"}]}]'

# Rule - Allow Corosync from subnet a
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --ip-permissions '[{"IpProtocol": "udp", "FromPort": '5404', "ToPort": '5406', "IpRanges": [{"CidrIp": "'${SUBNET_A}'", "Description": "Allow Corosync from subnet a"}]}]'

# Rule - Allow Corosync from subnet b
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --ip-permissions '[{"IpProtocol": "udp", "FromPort": '5404', "ToPort": '5406', "IpRanges": [{"CidrIp": "'${SUBNET_B}'", "Description": "Allow Corosync from subnet b"}]}]'

# Rule - Allow PostgreSQL from any
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --ip-permissions '[{"IpProtocol": "tcp", "FromPort": '5432', "ToPort": '5432', "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "Allow PostgreSQL from any"}]}]'

# Create Key Pair
KEY_NAME="$PROJECT-$ENVIRONMENT-$CREATOR"
aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text >~/.ssh/"$KEY_NAME".pem
chmod 0600 ~/.ssh/"$KEY_NAME".pem

# Run instances
IMAGE_ID="$(aws ec2 describe-images --owner 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*" "Name=virtualization-type,Values=hvm" --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)"

NAME="$NODE_01_NAME"
SUBNET="$SUBNET_A_ID"
NODE_01_ID="$(aws ec2 run-instances --image-id "$IMAGE_ID" --instance-type "$INSTANCE_TYPE" --count 1 --subnet-id "$SUBNET" --security-group-ids "$SG_ID" --instance-initiated-shutdown-behavior stop --key-name "$KEY_NAME" --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='${NAME}'},{Key=Project,Value='${PROJECT}'},{Key=Environment,Value='${ENVIRONMENT}'},{Key=Creator,Value='${CREATOR}'}]' --query 'Instances[].[InstanceId]' --output text)"
aws ec2 wait instance-running --instance-ids "$NODE_01_ID"

NAME="$NODE_02_NAME"
SUBNET="$SUBNET_B_ID"
NODE_02_ID="$(aws ec2 run-instances --image-id "$IMAGE_ID" --instance-type "$INSTANCE_TYPE" --count 1 --subnet-id "$SUBNET" --security-group-ids "$SG_ID" --instance-initiated-shutdown-behavior stop --key-name "$KEY_NAME" --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='${NAME}'},{Key=Project,Value='${PROJECT}'},{Key=Environment,Value='${ENVIRONMENT}'},{Key=Creator,Value='${CREATOR}'}]' --query 'Instances[].[InstanceId]' --output text)"
aws ec2 wait instance-running --instance-ids "$NODE_01_ID"

# Allocate EIP
ELASTIC_IP="$(aws ec2 allocate-address --domain vpc --query "PublicIp" --output text)"
ALLOCATION_ID="$(aws ec2 describe-addresses --filters "Name=public-ip,Values=$ELASTIC_IP" --query "Addresses[].AllocationId" --output text)"

# Associate EIP with node 01
aws ec2 associate-address --allocation-id "$ALLOCATION_ID" --instance-id "$NODE_01_ID"

# Add tags to created resources
for resource in $VPC_ID $SUBNET_A_ID $SUBNET_B_ID $IGW_ID $SG_ID $NODE_01_ID $NODE_02_ID $ALLOCATION_ID; do
    aws ec2 create-tags --resources "$resource" --tags Key=Project,Value="$PROJECT" Key=Environment,Value="$ENVIRONMENT" Key=Creator,Value="$CREATOR"
done

# Add name to VPC
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="$PROJECT"

# Get instances ips
NODE_01_IP="$(aws ec2 describe-instances --filter --instance-ids "$NODE_01_ID" --query "Reservations[].Instances[].[PublicIpAddress]" --output text)"
NODE_02_IP="$(aws ec2 describe-instances --filter --instance-ids "$NODE_02_ID" --query "Reservations[].Instances[].[PublicIpAddress]" --output text)"

# Fill PostgreSQL password file
touch "$PGPASSFILE"
echo "$ELASTIC_IP":5432:postgres:"$PG_CUSTOM_USER_NAME":"$PG_CUSTOM_USER_PASSWORD" >"$PGPASSFILE"
chmod 0600 "$PGPASSFILE"

# Fill Ansible inventory file
echo "[postgresql]" >"$ANSIBLE_INVENTORY"
echo "$NODE_01_NAME" ansible_user="$ANSIBLE_USER" ansible_ssh_private_key_file=~/.ssh/"$KEY_NAME".pem ansible_ssh_host="$ELASTIC_IP" >>"$ANSIBLE_INVENTORY"
echo "$NODE_02_NAME" ansible_user="$ANSIBLE_USER" ansible_ssh_private_key_file=~/.ssh/"$KEY_NAME".pem ansible_ssh_host="$NODE_02_IP" >>"$ANSIBLE_INVENTORY"
echo  >>"$ANSIBLE_INVENTORY"
echo "[postgresql-master]" >>"$ANSIBLE_INVENTORY"
echo "$NODE_MASTER" >>"$ANSIBLE_INVENTORY"
echo  >>"$ANSIBLE_INVENTORY"
echo "[postgresql-slave]" >>"$ANSIBLE_INVENTORY"
echo "$NODE_SLAVE" >>"$ANSIBLE_INVENTORY"
echo  >>"$ANSIBLE_INVENTORY"
echo "[cluster-master]" >>"$ANSIBLE_INVENTORY"
echo "$NODE_MASTER" >>"$ANSIBLE_INVENTORY"
echo  >>"$ANSIBLE_INVENTORY"
echo "[cluster-slave]" >>"$ANSIBLE_INVENTORY"
echo "$NODE_SLAVE" >>"$ANSIBLE_INVENTORY"

# Fill Ansible environment variables file
echo \#\!/usr/bin/env bash >"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo >>"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo "# Define ansible environment variables" >>"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo export ELASTIC_IP="$ELASTIC_IP" >>"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo export ALLOCATION_ID="$ALLOCATION_ID" >>"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo export ANSIBLE_HOST_KEY_CHECKING=False >>"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo export ANSIBLE_INVENTORY=hosts >>"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo export CIDR_BLOCK="$CIDR_BLOCK" >>"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo export PGPASSFILE="$PGPASSFILE" >>"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo export PG_CUSTOM_USER_NAME="$PG_CUSTOM_USER_NAME" >>"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo export PG_CUSTOM_USER_PASSWORD="$PG_CUSTOM_USER_PASSWORD" >>"$ANSIBLE_ENVIRONMENT_VARIABLES"
echo export PG_REPLICATION_USER_PASSWORD="$PG_REPLICATION_USER_PASSWORD" >>"$ANSIBLE_ENVIRONMENT_VARIABLES"