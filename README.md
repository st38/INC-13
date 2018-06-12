# Task INC-13

 1. [Goals](#goals)
 2. [Description](#description)
 3. [Requirements](#requirements)
 4. [General plan](#general-plan)
 5. [Duration](#duration)
 6. [Considerations](#considerations)
 7. [Usage](#usage)
 8. [Verification](#verification)
 9. [Recovery failed node](#recovery-failed-node)
 10. [Remove environment](#remove-environment)


## Goals

 1. Setup postgresql HA cluster


## Description

 Set up postgresql HA cluster with automatic failover using Pacemaker on regular EC2 instances (t2.micro).

## Requirements

 1. Linux host with [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/installing.html) and [Ansible](https://docs.ansible.com/ansible/2.3/intro_installation.html) installed.
 2. AWS account with AmazonEC2FullAccess permissions.


## General plan

 1. Create two instances.
 2. Configure secirity group for communication.
 3. Allocate AWS Elastic IP.
 4. Install and configure PostgreSQL.
 5. Install and configure Pacemaker with Corosync.
 6. Get Packemaker ocf for AWS Elastic IP and PostgreSQL.
 7. Configure cluster.
 8. Verify results.


## Duration

 This task may be accomplished in for about 15 minutes.


## Considerations

 1. This setup create a PostgreSQL [Synchronous Streaming Replication](https://wiki.postgresql.org/wiki/Streaming_Replication).


## Usage

 1. Get project code from GitHub:
	```bash
	USERNAME=st38
	REPOSITORY=INC-13
	
	git clone https://github.com/"$USERNAME"/"$REPOSITORY"
	cd "$REPOSITORY"
	```

 2. Edit project variables:
	```bash
	vi variables.sh
	```

 3. Provide AWS credentials and variables for Ansible playbooks:
	```bash
	export AWS_ACCESS_KEY_ID="access key"
	export AWS_SECRET_ACCESS_KEY="secret access key"
	export AWS_DEFAULT_REGION="eu-central-1"
	
	export PG_CUSTOM_USER_NAME="username"
	export PG_CUSTOM_USER_PASSWORD="password"
	export PG_REPLICATION_USER_PASSWORD="password"
	```

 4. Create AWS environment by invoking create-environment.sh script:
	```bash
	bash create-environment.sh
	```

 5. Load variables created by above runned script:
	```bash
	cd ansible
	
	source ansible-variables.sh
	```

 6. Run Ansible playbook:
	```bash
	ansible-playbook pg-cluster.yml
	```


## Verification

 1. View Pacemaker cluster status:
	```bash
	ansible cluster-master --become -a "crm_mon -Afr -1"
	```

 2. Verify PostgreSQL replication status:
	```bash
	# For master
	ansible cluster-master --become --become-user postgres -a "psql -c 'SELECT client_addr,sync_state from pg_stat_replication;'"
	ansible cluster-master --become --become-user postgres -a "psql -c 'SELECT pg_current_xlog_location();'"
	
	#For slave
	ansible cluster-slave --become --become-user postgres -a "psql -c 'SELECT pg_last_xlog_replay_location();'"
	```

 3. Run script to monitor cluster failover:
	
	Make sure that you have PostgreSQL clinet tools installed:
	```bash
	echo 'deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main' | sudo tee --append /etc/apt/sources.list.d/pgdg.list
	wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
	sudo apt-get update
	sudo apt-get install postgresql-client-9.6
	```

	Open second terminal:
	```bash
	REPOSITORY=INC-13
	
	cd "$REPOSITORY"/ansible
	
	source ansible-variables.sh
	```

	Run the following script:
	```bash
	while :; do
	echo "$(date +%Y-%m-%d" "%H:%M"  "%S"   "%2N)" | grep ".*"
	STAT="$(psql -h "$ELASTIC_IP" -U "$PG_CUSTOM_USER_NAME" -d postgres -c 'SELECT client_addr,sync_state from pg_stat_replication;' | grep "|" | grep -v "client_addr")"
	XLOG="$(psql -h "$ELASTIC_IP" -U "$PG_CUSTOM_USER_NAME" -d postgres -c 'SELECT pg_current_xlog_location();' | grep "/" --color=never)"
	echo "$STAT" "$XLOG"
	sleep 1
	done
	```

 4. Standby node01 from cluster in initial terminal window:
	```bash
	ansible cluster-master --become -a "crm node standby node01"
	```
	On the second terminal we may see that PostgreSQL is resumed to normal in for about 10 seconds.

 5. View Pacemaker cluster status again:
	```bash
	ansible cluster-master --become -a "crm_mon -Afr -1"
	```
	Now, node02 is PostgreSQL master and Elastic IP is on it.

 6. Bring node01 back online:
	```bash
	ansible cluster-master --become -a "crm node online node01"
	```

 7. And verify Pacemaker cluster status:
	```
	ansible cluster-master --become -a "crm_mon -Afr -1"
	```

## Recovery failed node

 1. The following steps should be done on failed node in order to start PostgreSQL service on it:
	```bash
	# Login on to the host
	ssh -i .ssh/keypair.pem ubuntu@IP
	
	# Remove lock file
	sudo rm /var/lib/postgresql/9.6/tmp/PGSQL.lock
	
	# Cleanup Pacemaker cluster resource
	sudo crm resource cleanup msPostgresql
	```

## Remove environment

 1. Remove created AWS environment by invoking remove-environment.sh script:
	```bash
	cd ..
	
	bash create-environment.sh
	```