#!/bin/bash

# Starting script for ML
# v0.1
# kwijethu@cern.ch


function template(){

	srcFile=$1
	destFile=$2

	echo "=========== Templating the File ==========="
	echo "+ Source File: $srcFile"
	echo "+ Destination File: $destFile"
	echo ""

	# Create backup of the original file if it exists
	[ -f $destFile ] && cp -f $destFile "$destFile.orig"
	cp $srcFile $destFile

	# Apply lines changes
	echo ">>> Applying Changes"
	for key in "${!changes[@]}"
	do
		# Find partial matches and replace
		echo "Change key: $key to value: ${changes[$key]}"
		sed -i "s|$key|${changes[$key]}|" $destFile
	done
	unset changes && echo ""
  
	# Append new Lines
	echo ">>> Adding new lines"
	for i in "${add[@]}"
	do
		echo "+++ $i"
		echo "$i" >> $destFile
	done
	unset add && echo ""

	# Remove existing lines
	echo ">>> Removing existing lines"
	for i in "${rmv[@]}"
	do
	# Find exact word matches and delete the line
	echo "--- $i"
	sed -i "/$i\b/d" $destFile
	done
	unset rmv && echo ""

	echo " --- Templating Complete ---"
	echo ""
  
}

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

	add+=(${siteConfiguration[MONALISA_ADDMODULES_LIST]}); #TODO : find a site with "addModules” key and test
	add+=("^monLogTail{Cluster=AliEnServicesLogs,Node=CE,command=tail -n 15 -F $baseLogDir/CE/alien.log 2>&1}%3")
	add+=("*AliEnServicesStatus{monStatusCmd, localhost, \"logDir=$baseLogDir `dirname $0`/jalien-vobox CE mlstatus,timeout=800\"}%900")

	template "$farmHome/Service/myFarm/myFarm.conf" "$logDir/myFarm/myFarm.conf"

	# ========================================================================================
	# ml.properties

	declare -Ag changes
	for key in "${monalisaProperties[@]}"
	do 
		add+=($key)
	done

	location=${monalisaLDAPconfiguration[LOCATION]-${monalisaLDAPconfiguration[SITE_LOCATION]}} || ""
	country=${monalisaLDAPconfiguration[COUNTRY]-${monalisaLDAPconfiguration[SITE_COUNTRY]}} || ""
	long=${monalisaLDAPconfiguration[LONGITUDE]-${monalisaLDAPconfiguration[SITE_LONGITUDE]}} || "N/A"
	lat=${monalisaLDAPconfiguration[LATITUDE]-${monalisaLDAPconfiguration[SITE_LATITUDE]}} || "N/A"

	changes["^MonaLisa.Location.*"]="MonaLisa.Location=$location"
	changes["^MonaLisa.Country.*"]="MonaLisa.Country=$country"
	changes["^MonaLisa.LAT.*"]="MonaLisa.LAT=$lat"
	changes["^MonaLisa.LONG.*"]="MonaLisa.LONG=$long"

	template "$farmHome/Service/myFarm/ml.properties" "$logDir/myFarm/ml.properties"

	# ===================================================================================
	# ml.env
	
	declare -Ag changes
	changes["^FARM_NAME.*"]="FARM_NAME=\"${monalisaLDAPconfiguration[NAME]}\""
	changes["^FARM_HOME.*"]="FARM_HOME=\"$logDir/myFarm\""
	changes["^MONALISA_USER.*"]="MONALISA_USER=\"$(id -u -n)\""
	changes["^MonaLisa_HOME.*"]="$MonaLisa_HOME"

	template "$farmHome/Service/CMD/ml_env" "$logDir/myFarm/ml_env"

	# ============================= Export variables =====================================
	export CONFDIR="$logDir/myFarm"
	export ALICE_LOGDIR=$baseLogDir
	export JAVAOPTS=${monalisaLDAPconfiguration[JAVAOPTS]}
	# ===================================================================================
}

function check_liveness_ml(){
	pid=$(pgrep -n -u `id -u` -f -- "-DMonaLisa_HOME=")
	if [[ -z $pid ]]
	then
		return 1
	else
		return 0
	fi
}

function start_ml(){
	# Check if there is an existing instance
	check_liveness_ml
	if [[ $? == 0 ]]
	then
		echo "Existing instance of MonaLisa already running..." && exit 1
	fi
	
	confDir=$1
	farmHome=${MonaLisa_HOME} # MonaLisa package location should be defined as an environment variable

	if [[ -z $farmHome ]]
	then
		echo "Please point MonaLisa variable to the MonaLisa package location by setting the environment variable MonaLisa_HOME" && exit 1
	fi
	# ======================== Start templating config files  ========================
	ldapHostname=$2
	ldapPort=$3
	hostname=$4
	
	# Obtain site related configurations from LDAP
	siteLDAPQuery=$(ldapsearch -x -LLL -h $ldapHostname -p $ldapPort -b "host=$hostname,ou=Config,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch" 2> /dev/null )
	declare -A siteConfiguration
	while IFS= read -r line
	do
	#Ignore empty lines and create an associative array from ldap configuration
	if [[ ! -z $line ]]
	then
		key=$(echo $line| cut -d ":" -f 1 | xargs 2>/dev/null)
		val=$(echo $line | cut -d ":" -f 2- | xargs 2>/dev/null)
		val=$(envsubst <<< $val)
		siteConfiguration[${key^^}]=$val
	fi
	done <<< "$siteLDAPQuery"

	# Obtain MonAlisa service related configurations from LDAP
	siteName=${siteConfiguration[MONALISA]}
	if [[ -z $siteName ]]
	then
		echo "LDAP Configuration for MonaLisa configuration not found. Please set it up and try again." && exit 1
	fi
	monalisaLDAPQuery=$(ldapsearch -x -LLL -h $ldapHostname -p $ldapPort -b "name=$siteName,ou=MonaLisa,ou=Services,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch" 2> /dev/null)

	declare -A monalisaLDAPconfiguration
	monalisaProperties=()
	while IFS= read -r line
	do
	if [[ ! -z $line ]]
		then
		# Create a new array for addProperties
		if [[ $line = addProperties* ]];
		then
			val=$(echo $line | cut -d ":" -f 2- | xargs 2>/dev/null)
			monalisaProperties+=($val)
		else
			key=$(echo $line | cut -d ":" -f 1 | xargs 2>/dev/null)
			val=$(echo $line | cut -d ":" -f 2- | xargs 2>/dev/null)
			monalisaLDAPconfiguration[${key^^}]=$val
		fi
	fi
	done <<< "$monalisaLDAPQuery"

	echo "===================== Base Config ==================="
	for x in "${!siteConfiguration[@]}"; do printf "[%s]=%s\n" "$x" "${siteConfiguration[$x]}" ; done
	echo ""

	echo "===================== MonaLisa Properties ==================="
	for x in "${monalisaProperties[@]}"; do printf  "$x\n"  ; done
	echo ""

	echo "===================== MonaLisa Config ==================="
	for x in "${!monalisaLDAPconfiguration[@]}"; do printf "[%s]=%s\n" "$x" "${monalisaLDAPconfiguration[$x]}" ; done
	echo ""
	
	baseLogDir=${siteConfiguration[LOGDIR]}
	if [[ -z $baseLogDir ]]
	then
		baseLogDir="$HOME/ALICE/alien-logs"
		echo "LDAP doesn't define a particular log location, using the default ($baseLogDir)"
	fi

	logDir="$baseLogDir/MonaLisa"
	envFile="$logDir/ml-env.sh"
	mlConf="$confDir/ml.properties"
	mlEnv="$confDir/ml.env"
	envCommand="/cvmfs/alice.cern.ch/bin/alienv printenv MonaLisa"
	logFile="$logDir/ml-$(date '+%y%m%d-%H%M%S')-$$-log.txt"

	ceConf="$confDir/CE.properties"

	if [[ ! -f "$confDir" ]]; 
	then
		mkdir $confDir
	fi

	# Write log directory to CE.properties file
	if [[ -f "$ceConf" ]]; 
	then
		if  grep -q "LOGDIR" "$ceConf" 
		then
			sed -i "s|'^LOGDIR.*'|'LOGDIR=$baseLogDir'|" $destFile
		else
			echo "LOGDIR=$baseLogDir" >> "$ceConf"
		fi
	else
		echo "LOGDIR=$baseLogDir" > "$ceConf"
	fi


	# Read MonaLisa config files
	if [[ -f "$mlConf" ]]
	then
		declare -A monalisaConfiguration
		while IFS= read -r line
		do
		if [[ ! $line = \#* ]] && [[ ! -z $line ]]
			then
			key=$(echo $line| cut -d "=" -f 1 | xargs 2>/dev/null)
			val=$(echo $line | cut -d "=" -f 2- | xargs 2>/dev/null)
			monalisaConfiguration[${key^^}]=$val
		fi
		done <<< "$mlConf"
	fi

	# Reset the environment
	> $envFile

	# Bootstrap the environment e.g. with the correct X509_USER_PROXY
	[[ -f "$mlEnv" ]] && cat "$mlEnv" >> $envFile

	# Check for MonAlisa version 
	if [[ -n "${monalisaConfiguration[MonaLisa]}" ]]
	then
		envCommand="$envCommand/${monalisaConfiguration[MonaLisa]}"
	fi

	$envCommand >> $envFile

	source $envFile

	mkdir -p $logDir || { echo "Unable to create log directory at $logDir or log directory not found in LDAP configuration" && return; }
	echo "MonaLisa Log Directory: $logDir"
	echo "Started configuring MonAlisa..."
	echo ""

	setup $farmHome $logDir

	echo "Starting MonAlisa.... Please check $logFile for logs"
	(
		# In a subshell, to get the process detached from the parent
		cd $logDir
		nohup $farmHome/Service/CMD/ML_SER start > "$logFile" 2>&1 < /dev/null &
	)
}

function stop_ml(){
	echo "Stopping MonaLisa..."
	for pid in $(pgrep -u `id -u` -f -- '-DMonaLisa_HOME=')
	do
		# request children to shutdown
		kill -s HUP ${pid} 2>/dev/null
		kill -s TERM ${pid} 2>/dev/null
	done
}

function status_ml() {
	check_liveness_ml
	exit_code=$?
	if [[ $exit_code == 0 ]]
	then 
		echo -e "Status \t $exit_code \t MonaLisa Running"
	elif [[ $exit_code == 1 ]]
	then
		echo -e "Status \t $exit_code \t MonaLisa Not Running"
	fi
}

function run_monalisa() {
	if [[ $1 == "start" ]]
	then
		confDir=$2
		ldapHostname=$3
		ldapPort=$4
		hostname=$5
		start_ml $confDir $ldapHostname $ldapPort $hostname

	elif [[ $1 == "stop" ]]
	then
		stop_ml

	elif [[ $1 == "restart" ]]
	then
		stop_ml
		start_ml $confDir $ldapHostname $ldapPort $hostname

	elif [[ $1 == "mlstatus" ]]
	then
		status_ml

	else
	    echo "Command must be one of: 'start', 'stop', 'restart' or 'mlstatus'"
		return 2
	fi
}
