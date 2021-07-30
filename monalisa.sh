#!/bin/bash

# Starting script for MonaLisa
# v0.1

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

####################################################################################
# Templates a given configuration files(Add, delete or change content)
# Globals:
#   add: Array of lines to add to file
#	rmv: Array of lines to be removed from file
#	changes: Associative array of line to be changed {original_text:change_to_text}
# Arguments:
#   srcFile: Source file
#	destFile: Destination file
####################################################################################
function template(){

	srcFile=$1
	destFile=$2

	write_log "=========== Templating the File ==========="
	write_log "+ Source File: $srcFile"
	write_log "+ Destination File: $destFile"
	write_log ""

	# Create backup of the original file if it exists
	[ -f $destFile ] && cp -f $destFile "$destFile.orig"
	cp $srcFile $destFile

	# Apply lines changes
	write_log ">>> Applying Changes"
	for key in "${!changes[@]}"
	do
		# Find partial matches and replace
		write_log "Change key: $key to value: ${changes[$key]}"
		sed -i "s|$key|${changes[$key]}|" $destFile
	done
	unset changes && write_log ""
  
	# Append new Lines
	write_log ">>> Adding new lines"
	for i in "${add[@]}"
	do
		write_log "+++ $i"
		echo "$i" >> $destFile
	done
	unset add && write_log ""

	# Remove existing lines
	write_log ">>> Removing existing lines"
	for i in "${rmv[@]}"
	do
	# Find exact word matches and delete the line
	write_log "--- $i"
	sed -i "/$i\b/d" $destFile
	done
	unset rmv && write_log ""

	write_log " --- Templating Complete ---"
	write_log ""
  
}

#############################################################################################
# Setup MonaLisa
# Globals:
#   monalisaLDAPconfiguration: Associative array of MonaLisa configuration parameters in LDAP
#	baseLogDir: MonaLisa Log file. Defaults to ~/ALICE/alien-logs
#	ceLogFile: CE Log File
# Arguments:
#   farmHome: MonaLisa base package location
#	logDir: MonaLisa log directory
#############################################################################################
function setup() {

	farmHome=$1
	logDir=$2

	add=()
	rmv=()
	declare -Ag changes

	# Copy base templates to the local directory
	mkdir -p "$logDir/myFarm/"
   
	# ===================================================================================
	# myFarm.conf 

	# Convert multi-valued attribute to array
	while IFS= read -r line ; do add+=($line); done <<< "${siteConfiguration[MONALISA_ADDMODULES_LIST]}"
	add+=("^monLogTail{Cluster=AliEnServicesLogs,Node=CE,command=tail -n 15 -F $ceLogFile 2>&1}%3")
	add+=("*AliEnServicesStatus{monStatusCmd, localhost, \"logDir=$baseLogDir $(cd `dirname -- "$0"` &>/dev/null && pwd)/jalien-vobox.sh mlstatus ce,timeout=800\"}%900")

	template "$farmHome/Service/myFarm/myFarm.conf" "$logDir/myFarm/myFarm.conf"

	# ========================================================================================
	# ml.properties

	declare -Ag changes

	# Convert multi-valued attribute to array
	while IFS= read -r line ; do add+=($line); done <<< "${monalisaLDAPconfiguration[ADDPROPERTIES]}"

	location=${monalisaLDAPconfiguration[LOCATION]-${monalisaLDAPconfiguration[SITE_LOCATION]}} || ""
	country=${monalisaLDAPconfiguration[COUNTRY]-${monalisaLDAPconfiguration[SITE_COUNTRY]}} || ""
	long=${monalisaLDAPconfiguration[LONGITUDE]-${monalisaLDAPconfiguration[SITE_LONGITUDE]}} || "N/A"
	lat=${monalisaLDAPconfiguration[LATITUDE]-${monalisaLDAPconfiguration[SITE_LATITUDE]}} || "N/A"
	admin=${monalisaLDAPconfiguration[ADMINISTRATOR]-${monalisaLDAPconfiguration[SITE_ADMINISTRATOR]}} || "N/A"

	changes["^MonaLisa.Location.*"]="MonaLisa.Location=$location"
	changes["^MonaLisa.Country.*"]="MonaLisa.Country=$country"
	changes["^MonaLisa.LAT.*"]="MonaLisa.LAT=$lat"
	changes["^MonaLisa.LONG.*"]="MonaLisa.LONG=$long"
	changes["^MonaLisa.ContactEmail.*"]="MonaLisa.ContactEmail=$admin"

	template "$farmHome/Service/myFarm/ml.properties" "$logDir/myFarm/ml.properties"

	# ===================================================================================
	# ml.env
	
	declare -Ag changes
	changes["^FARM_NAME.*"]="FARM_NAME=\"${monalisaLDAPconfiguration[NAME]}\""
	changes["^FARM_HOME.*"]="FARM_HOME=\"$logDir/myFarm\""
	changes["^MONALISA_USER.*"]="MONALISA_USER=\"$(id -u -n)\""
	changes["^MonaLisa_HOME.*"]="MonaLisa_HOME=\"$MonaLisa_HOME\""

	template "$farmHome/Service/CMD/ml_env" "$logDir/myFarm/ml_env"

	# ============================= Export variables =====================================
	export CONFDIR="$logDir/myFarm"
	export ALICE_LOGDIR=$baseLogDir
	export JAVA_OPTS=${monalisaLDAPconfiguration[JAVAOPTS]}
	# ===================================================================================
}

#####################################
# MonaLisa liveness check
# Returns:
#   0 if process is running,else 1
#####################################
function check_liveness_ml(){
	
	pid=$(pgrep -n -u `id -u` -f -- "-DMonaLisa_HOME=")
	if [[ -z $pid ]]
	then
		return 1
	else
		return 0
	fi
}

#############################################################################################
# Start MonaLisa
# Globals:
#	siteConfiguration: Associative array of site configuration parameters in LDAP
#	monalisaLDAPconfiguration: Associative array of MonaLisa configuration parameters in LDAP
#   commonConfiguration: Associative array of JAliEn local configuration parameters
# Arguments:
#   confDir: AliEn configuration directory
#	ldapHostname: LDAP hostname
#	ldapPort: LDAP port
#	hostname: Site hostname
#############################################################################################
function start_ml(){

	# Check if there is an existing instance
	check_liveness_ml
	if [[ $? == 0 ]]
	then
		echo "Existing instance of MonaLisa already running..." && exit 1
	fi
	
	# ======================== Config generation from LDAP  ========================
	confDir=$1
	ldapHostname=$2
	ldapPort=$3
	hostname=$4
	nl='
	'
	nl=${nl:0:1}

	# Obtain site related configurations from LDAP
	siteLDAPQuery=$(ldapsearch -x -LLL -h $ldapHostname -p $ldapPort -b "host=$hostname,ou=Config,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch" 2> /dev/null )
	declare -A siteConfiguration

	while IFS= read -r line
	do
	#Ignore empty lines and create an associative array from ldap configuration
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

	# Obtain MonAlisa service related configurations from LDAP
	siteName=${siteConfiguration[MONALISA]}
	if [[ -z $siteName ]]
	then
		echo "LDAP Configuration for MonaLisa configuration not found. Please set it up and try again." && exit 1
	fi

	ldapBase="ou=MonaLisa,ou=Services,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch"
	ldapFilter="(&(objectClass=AliEnMonaLisa)(name=$siteName))"
	monalisaLDAPQuery=$(ldapsearch -x -LLL -h $ldapHostname -p $ldapPort -b $ldapBase "$ldapFilter" |
			perl -p00e 's/\n //g' | envsubst
        )

	declare -A monalisaLDAPconfiguration

	while IFS= read -r line
	do
	if [[ ! -z $line ]]
		then

		key=$(echo "$line" | cut -d ":" -f 1)
    	val=$(echo "$line" | cut -d ":" -f 2- | sed s/.//)

		key=${key^^}
		prev=${monalisaLDAPconfiguration[$key]}
		prev=${prev:+$prev$nl}

		monalisaLDAPconfiguration[$key]=$prev$val
	fi
	done <<< "$monalisaLDAPQuery"
	
	baseLogDir=$(echo "${siteConfiguration[LOGDIR]}" | envsubst)

	if [[ -z $baseLogDir ]]
	then
		baseLogDir="$HOME/ALICE/alien-logs"
		echo "LDAP doesn't define a particular log location, using the default ($baseLogDir)"
	fi

	logDir="$baseLogDir/MonaLisa"
	setupLogFile="$logDir/ML-config-inputs.txt"
	ceLogFile="$baseLogDir/CE.log.0"
	envFile="$logDir/ml-env.sh"
	commonConf="$confDir/version.properties"
	mlEnv="$confDir/ml.env"
	envCommand="/cvmfs/alice.cern.ch/bin/alienv printenv MonaLisa"

	> $setupLogFile

	write_log "========== VObox Config =========="
	for x in "${!siteConfiguration[@]}"; do printf "[%s]=%s\n" "$x" "${siteConfiguration[$x]}" >> $setupLogFile ; done
	write_log "" 

	write_log "========== MonaLisa Config ==========" 
	for x in "${!monalisaLDAPconfiguration[@]}"; do printf "[%s]=%s\n" "$x" "${monalisaLDAPconfiguration[$x]}" >> $setupLogFile ; done
	write_log ""


	# Read MonaLisa config files
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
	write_log "========== Local Configuration start =========="
	for x in "${!commonConfiguration[@]}"
	do
		printf "[%s]=%s\n" "$x" "${commonConfiguration[$x]}" >> $setupLogFile
	done
	write_log "========== Local Configuration end =========="
	write_log ""

	# Reset the environment
	> $envFile

	# Bootstrap the environment e.g. with the correct X509_USER_PROXY
	[[ -f "$mlEnv" ]] && cat "$mlEnv" >> $envFile

	# If a custom MonaLisa package is declared, use that package as MonaLisa_HOME
	if [[ -n "${commonConfiguration[MONALISA_HOME]}" ]]
	then
		echo "export MonaLisa_HOME=${commonConfiguration[MONALISA_HOME]};" >> $envFile
	else
		# If a specific MonaLisa package is declared, use that package 
		if [[ -n "${commonConfiguration[MONALISA]}" ]]
		then
			envCommand="$envCommand/${commonConfiguration[MONALISA]}"
		fi

		$envCommand | grep . >> $envFile || exit 1
	fi
	source $envFile 

	farmHome=${MonaLisa_HOME} # MonaLisa package location should be defined as an environment variable or defined in version.properties file

	if [[ -z $farmHome ]]
	then
		echo "Please point MonaLisa variable to the MonaLisa package location by setting the environment variable MonaLisa_HOME"
		exit 1
	fi

	# ======================== Start templating config files  ========================

	if ! mkdir -p $logDir
	then
		echo "Unable to create log directory at $logDir"
		return 1
	fi
	echo "MonaLisa Log Directory: $logDir"
	echo ""
	echo "Started configuring MonaLisa..."
	echo ""

	setup $farmHome $logDir

	echo "Starting MonaLisa...."
	(
		# In a subshell, to ensure the process will be detached from the parent
		cd $logDir
		$farmHome/Service/CMD/ML_SER start < /dev/null
	)
}

###################
# Stop MonaLisa
###################
function stop_ml(){

	echo "Stopping MonaLisa..."
	
	for pid in $(pgrep -u `id -u` -f -- '-DMonaLisa_HOME=')
	do
		# request children to shutdown
		kill -s HUP $pid &>/dev/null
		sleep 1 ; echo -n "."
		kill -s HUP $pid &>/dev/null
		sleep 1 ; echo -n "."
		kill -s TERM $pid &>/dev/null
		sleep 2
	done

	echo "Stopped MonaLisa..."
}

###################################
# Check MonaLisa status
# Arguments:
#   $command: "status" or "mlstatus"
# Returns: 
#	0 if process is running,else 1
###################################
function status_ml() {
	command=$1

	check_liveness_ml
	exit_code=$?

	[[ $exit_code == 0 ]] && not= || not=' Not'

	if [[ "$command" == mlstatus ]]
	then
		echo -e "Status\t$exit_code\tMessage\tMonaLisa$not Running"
	else
		echo -e "MonaLisa$not Running"
	fi

}

function run_monalisa() {
	command=$1

	if [[ $command = "start" ]]
	then
		confDir=$2
		ldapHostname=$3
		ldapPort=$4
		hostname=$5
		start_ml $confDir $ldapHostname $ldapPort $hostname

	elif [[ $command = "stop" ]]
	then
		stop_ml

	elif [[ $command = "restart" ]]
	then
		stop_ml
		start_ml $confDir $ldapHostname $ldapPort $hostname

	elif [[ $command =~ "status" ]]
	then
		status_ml $command

	else
	    echo "Command must be one of: 'start', 'stop', 'restart' or 'mlstatus'"
		return 2
	fi
}
