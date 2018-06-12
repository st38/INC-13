#!/usr/bin/env bash

# Define variables
export PROJECT="PG-HA-Cluster"
export ENVIRONMENT="Test"
export CREATOR="VD"
export VPC_NAME="$PROJECT"
export CIDR_BLOCK="192.168.0.0/16"
export SUBNET_A="192.168.10.0/24"
export SUBNET_B="192.168.20.0/24"
export AZ_A="${AWS_DEFAULT_REGION}a"
export AZ_B="${AWS_DEFAULT_REGION}b"
export SG_NAME="$PROJECT"
export SG_DESCRIPTION="$PROJECT"
export INSTANCE_TYPE="t2.nano"
export NODE_01_NAME="node01"
export NODE_02_NAME="node02"
export NODE_MASTER="$NODE_01_NAME"
export NODE_SLAVE="$NODE_02_NAME"
export ANSIBLE_PLAYBOOKS_FOLDER="ansible"
export ANSIBLE_INVENTORY="$ANSIBLE_PLAYBOOKS_FOLDER/hosts"
export ANSIBLE_USER="ubuntu"
export ANSIBLE_ENVIRONMENT_VARIABLES="$ANSIBLE_PLAYBOOKS_FOLDER/ansible-variables.sh"
export PGPASSFILE=~/.pgpass