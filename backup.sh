#! /bin/sh


#	 _                _                     _     
#	| |__   __ _  ___| | ___   _ _ __   ___| |__  
#	| '_ \ / _` |/ __| |/ / | | | '_ \ / __| '_ \ 
#	| |_) | (_| | (__|   <| |_| | |_) |\__ \ | | |
#	|_.__/ \__,_|\___|_|\_\\__,_| .__(_)___/_| |_|
#	                            |_|               


# Hostname of the backup server. Entry in the ${HOME}/.ssh/config is required.
BACKUP_SERVER=""

# Backup target directiory on the backup server.
BACKUP_LOCATION="/backup"

# Place for logs.
LOG_FILE="/var/log/backup.log"

# backup.conf file should contain the '\n' separated list of files/directories for the backup.
CONFIG_FILE="${HOME}/.config/backup.conf"

# Directory for the backup
BACKUP_FOLDER=$(date +%F_%H-%M_backup)

function check_config {
	if [ ! -s ${CONFIG_FILE} ]
	then
		echo "${CONFIG_FILE} does not exist"
		echo "[$(date)] Performing the backup: Failure" >> ${LOG_FILE}
		exit 1
	fi
}

function check_backup_server {
	[ -z ${BACKUP_SERVER} ] && 
	echo "Variable BACKUP_SERVER is empty" && 
	echo "[$(date)] Performing the backup: Failure" >> ${LOG_FILE} && 
	exit 1

	# Get IP of the backup server.
	BACKUP_SERVER_IP=$(
		grep "Host" ${HOME}/.ssh/config | 
		awk -v host="Host ${BACKUP_SERVER}" '{
			if(flag==1){
				print $0
				flag=0
			}   
			if($0~host){
				flag=1
			}
		}' | 
		grep -o "[0-9\.]\+"
	)	

	[ -z ${BACKUP_SERVER_IP} ] &&
	echo "${BACKUP_SERVER}: No such a host in the ${HOME}/.ssh/config" &&
	echo "[$(date)] Performing the backup: Failure" >> ${LOG_FILE} &&
	exit 1
	
	# Check connectivity with the server.
	ping -q -c 1 -W 1 "${BACKUP_SERVER_IP}" > /dev/null
	if [ $? -eq 0 ]
	then
		# Check backup location on the server.
		ssh ${BACKUP_SERVER} test -d ${BACKUP_LOCATION}
		if [ ! $? -eq 0 ]
		then
			echo "Directory ${BACKUP_LOCATION} does not exists on the backup server"
			exit 1
		else 
			ssh ${BACKUP_SERVER} test -d "${BACKUP_LOCATION}/${BACKUP_FOLDER}" 
			if [ $? -eq 0 ]
			then
				echo "Seems like the backup directory ${BACKUP_FOLDER} already exists on the backup server" 
				exit 1
			else
				ssh ${BACKUP_SERVER} mkdir "${BACKUP_LOCATION}/${BACKUP_FOLDER}"
				echo "Created directory ${BACKUP_LOCATION}/${BACKUP_FOLDER} on the backup server"
			fi

		fi
	else
		echo "No connection with the ${BACKUP_SERVER}"
		exit 1
	fi
}

function do_the_backup {
	echo "[$(date)] Performing the backup: Start" >> ${LOG_FILE}
	while read -r backup_file
	do
		echo "Creating backup of ${backup_file}"
		file_name=$(basename "${backup_file}")
		tar -cf - --absolute-names "${backup_file}" 2>&1 | pv -s "$(du -sb "${backup_file}"| awk '{print $1}')" | xz > "/tmp/${file_name}.tar.xz"
		echo "Moving ${file_name}.tar.xz to the backup server."
		scp "/tmp/${file_name}.tar.xz" "${BACKUP_SERVER}:${BACKUP_LOCATION}/${BACKUP_FOLDER}"
		rm -rf "/tmp/${file_name}.tar.xz"
	done < "$CONFIG_FILE"
	echo "Done!"
	echo "[$(date)] Performing the backup: Success" >> ${LOG_FILE}
}

check_config
check_backup_server
do_the_backup
