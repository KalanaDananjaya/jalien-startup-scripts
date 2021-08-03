#!/bin/bash

# JAliEn Startup Scripts - CE
# v1.0
# Authors: Kalana Dananjaya, Maarten Litmaath, Costin Grigoras(kwijethu@cern.ch,Maarten.Litmaath@cern.ch,Costin.Grigoras@cern.ch)
# 2021-08-03

ceClassName=alien.site.ComputingElement

##############################################
# Write log to file
# Globals:
#   setupLogFile: Log file for MonaLisa setup
# Arguments:
#   $1: String to log
###############################################
function write_log(){
	echo $1 >> $setupLogFile
}

#############################################################################################
# Stop CE
# Globals:
#	ceClassName : Computing Element classname
#############################################################################################
function stop_ce() {
	echo "Stopping JAliEn CE..."
	pkill -TERM -f $ceClassName
	sleep 3

	status_ce || return 0

	echo "Killing JAliEn CE..."
	pkill -KILL -f $ceClassName

	! status_ce
}

#############################################################################################
# CE liveness check
# Returns:
#   0 if process is running,else 1
#############################################################################################
function check_liveness_ce(){
	if ps uxwww | grep "[ ]$ceClassName" > /dev/null
	then
		return 0
	else
		return 1
	fi
}

###################################
# Check CE status
# Arguments:
#   $command: "status" or "mlstatus"
# Returns: 
#	0 if process is running,else 1
###################################
function status_ce() {
	command=$1

	check_liveness_ce
	exit_code=$?

	[[ $exit_code == 0 ]] && not= || not=' Not'

	if [[ "$command" == mlstatus ]]
	then
		echo -e "Status\t$exit_code\tMessage\tCE$not Running"
	else
		echo -e "CE$not Running"
	fi

	return $exit_code
}

#############################################################################################
# Start MonaLisa
# Globals:
#	siteConfiguration: Associative array of site configuration parameters in LDAP
#   commonConfiguration: Associative array of JAliEn local configuration parameters
# Arguments:
#   confDir: AliEn configuration directory
#	ldapHostname: LDAP hostname
#	ldapPort: LDAP port
#	hostname: Site hostname
#############################################################################################
function start_ce(){
	confDir=$1
	ldapHostname=$2
	ldapPort=$3
	hostname=$4
	nl='
	'
	nl=${nl:0:1}

	if check_liveness_ce
	then
		echo "JAliEn CE already running"
		return 0
	fi

	# Obtain site related configurations from LDAP
	ldapBase="ou=Sites,o=alice,dc=cern,dc=ch"
	ldapFilter="(&(objectClass=AliEnHostConfig)(host=$hostname))"

	siteLDAPQuery=$(
		ldapsearch -x -LLL -h $ldapHostname -p $ldapPort -b $ldapBase "$ldapFilter" |
		perl -p00e 's/\n //g' | envsubst
	)

	declare -A siteConfiguration
	while IFS= read -r line
	do
		#Ignore empty lines and create an associative array from LDAP configuration
		if [[ ! -z $line ]]
		then
			key=$(echo "$line" | cut -d ":" -f 1 )
			val=$(echo "$line" | cut -d ":" -f 2- | sed s/.//)

			key=${key^^}
			prev=${siteConfiguration[$key]}
			prev=${prev:+$prev$nl}

			siteConfiguration[$key]=$prev$val
		fi
	done <<< "$siteLDAPQuery"

	baseLogDir=$(echo "${siteConfiguration[LOGDIR]}" | envsubst)
	if [[ -z $baseLogDir ]]
	then
		baseLogDir="$HOME/ALICE/alien-logs"
		echo "LDAP doesn't define a particular log location, using the default ($baseLogDir)"
	fi

	logDir="$baseLogDir/CE"
	setupLogFile="$logDir/CE-config-inputs.txt"
	commonConf="$confDir/version.properties"
	ceEnv="$confDir/CE.env"
	envCommand="/cvmfs/alice.cern.ch/bin/alienv printenv JAliEn"

	> $setupLogFile

	# Read JAliEn config files
	if [[ -f "$commonConf" ]]
	then
		declare -A commonConfiguration

		while IFS= read -r line
		do
			if [[ ! $line = \#* ]] && [[ ! -z $line ]]
			then
				key=$(echo "$line" | cut -d "=" -f 1 )
				val=$(echo "$line" | cut -d "=" -f 2- )

				key=${key^^}
				prev=${commonConfiguration[$key]}
				prev=${prev:+$prev$nl}

				commonConfiguration[$key]=$prev$val
			fi
		done < "$commonConf"
	fi

	write_log ""
	write_log "===================== Local Configuration start ==================="
	for x in "${!commonConfiguration[@]}"
	do
		printf "[%s]=%s\n" "$x" "${commonConfiguration[$x]}" >> $setupLogFile
	done
	write_log "===================== Local Configuration end ==================="
	write_log ""

	envFile="$logDir/CE-env.sh"
	pidFile="$logDir/CE.pid"
	
	if ! mkdir -p $logDir
	then
		echo "Unable to create log directory at $logDir"
		return 1
	fi

	# Reset the environment
	> $envFile

	# Bootstrap the environment e.g. with the correct X509_USER_PROXY
	[[ -f "$ceEnv" ]] && cat "$ceEnv" >> $envFile

	# Check for JAliEn version
	if [[ -n "${commonConfiguration[JALIEN]}" ]]
	then
		envCommand="$envCommand/${commonConfiguration[JALIEN]}"
	fi

	$envCommand | grep . >> $envFile || return 1

	logFile="$logDir/CE-jvm-$(date '+%y%m%d-%H%M%S')-$$-log.txt"

	echo -e "Starting JAliEn CE...\nJVM log:$logFile"
	(
		# In a subshell, to get the process detached from the parent
		source $envFile
		cd $logDir
		nohup jalien $ceClassName > "$logFile" 2>&1 < /dev/null &
		echo $! > "$pidFile"
	)

	sleep 3
	status_ce
}

function run_ce() {
	command=$1

	if [[ $command = "start" ]]
	then
		confDir=$2
		ldapHostname=$3
		ldapPort=$4
		hostname=$5
		start_ce $confDir $ldapHostname $ldapPort $hostname

	elif [[ $command = "stop" ]]
	then
		stop_ce

	elif [[ $command = "restart" ]]
	then
		stop_ce
		start_ce $confDir $ldapHostname $ldapPort $hostname

	elif [[ $command =~ "status" ]]
	then
		status_ce $command

	else
		echo "Command must be one of: 'start', 'stop', 'restart' or '(ml)status'"
		return 2
	fi
}
