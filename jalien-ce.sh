#!/bin/bash

# Starting script for CE
# v0.1
# kwijethu@cern.ch

function stop_ce() {
	echo "Stopping JAliEn CE"
	pkill -f $1
}

function check_liveness_ce(){
	pid=$(ps -aux | grep -i 'alien.site.ComputingElement=' | grep -v grep)
	if [[ -z $pid ]]
	then
		return 1
	else
		return 0
	fi
}

function status_ce() {
	check_liveness_ce
	exit_code=$?
	if [[ $exit_code == 0 ]]
	then 
		echo -e "Status \t $exit_code \t CE Running"
	elif [[ $exit_code == 1 ]]
	then
		echo -e "Status \t $exit_code \t CE Not Running"
	fi
}

function start_ce(){
	confDir=$1
	className=$2

	ceConf="$confDir/CE.properties"
	ceEnv="$confDir/CE.env"
	envCommand="/cvmfs/alice.cern.ch/bin/alienv printenv JAliEn"

	# Read JAliEn config files
	if [[ -f "$ceConf" ]]
	then
		declare -A jalienConfiguration

		while IFS= read -r line
		do
		if [[ ! $line = \#* ]] && [[ ! -z $line ]]
		then
			key=$(echo $line | cut -d "=" -f 1  | xargs)
			val=$(echo $line | cut -d "=" -f 2- | xargs)
			jalienConfiguration[${key^^}]=$val
		fi
		done < "$ceConf"
	fi

	logDir=${jalienConfiguration[LOGDIR]-"${HOME}/ALICE/alien-logs"}/CE
	envFile="$logDir/CE-env.sh"
	pidFile="$logDir/CE.pid"
	mkdir -p $logDir || { echo "Unable to create log directory at $logDir" && return; }

	# Reset the environment
	> $envFile

	# Bootstrap the environment e.g. with the correct X509_USER_PROXY
	[[ -f "$ceEnv" ]] && cat "$ceEnv" >> $envFile

	# Check for JAliEn version
	if [[ -n "${jalienConfiguration[JALIEN]}" ]]
	then
		envCommand="$envCommand/${jalienConfiguration[JALIEN]}"
	fi

	$envCommand >> $envFile
	source $envFile

	logFile="$logDir/CE-jvm-$(date '+%y%m%d-%H%M%S')-$$-log.txt"

	echo "Starting JAliEn CE.... Please check $logFile for logs"
	(
		# In a subshell, to get the process detached from the parent
		cd $logDir
		nohup jalien $className > "$logFile" 2>&1 < /dev/null &
		echo $! > "$pidFile"
	)
}

function run_ce() {
	command=$1
	confDir=$2
	className=alien.site.ComputingElement

	if [[ $command = "start" ]]
	then
		start_ce $confDir $className

	elif [[ $command = "stop" ]]
	then
		stop_ce $className

	elif [[ $command = "restart" ]]
	then
		stop_ce $className
		start_ce $confDir $className

	elif [[ $command = "mlstatus" ]]
	then
		status_ce

	else
	echo "Command must be one of: 'start', 'stop', 'restart' or 'mlstatus'"
	return 2
	fi
}
