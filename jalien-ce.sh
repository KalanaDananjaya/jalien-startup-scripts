#!/bin/bash

# Starting script for CE
# v0.1
# kwijethu@cern.ch

ceClassName=alien.site.ComputingElement

function stop_ce() {
	echo "Stopping JAliEn CE..."
	pkill -TERM -f $ceClassName
	sleep 3

	status_ce || return 0

	echo "Killing JAliEn CE..."
	pkill -KILL -f $ceClassName

	! status_ce
}

function check_liveness_ce(){
	if ps uxwww | grep "[ ]$ceClassName" > /dev/null
	then
		return 0
	else
		return 1
	fi
}

function status_ce() {
	cmd=$1

	check_liveness_ce
	exit_code=$?

	[[ $exit_code == 0 ]] && not= || not=' Not'

	if [[ "$cmd" == mlstatus ]]
	then
		echo -e "Status\t$exit_code\tMessage\tCE$not Running"
	else
		echo -e "CE$not Running"
	fi

	return $exit_code
}

function start_ce(){
	confDir=$1
	
	if check_liveness_ce
	then
		echo "JAliEn CE already running"
		return 0
	fi

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
	mkdir -p $logDir || { echo "Unable to create log directory at $logDir" && return 1; }

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

	echo -e "Starting JAliEn CE...  JVM log:\n$logFile"
	(
		# In a subshell, to get the process detached from the parent
		cd $logDir
		nohup jalien $ceClassName > "$logFile" 2>&1 < /dev/null &
		echo $! > "$pidFile"
	)

	sleep 3
	status_ce
}

function run_ce() {
	command=$1
	confDir=$2

	if [[ $command = "start" ]]
	then
		start_ce $confDir

	elif [[ $command = "stop" ]]
	then
		stop_ce

	elif [[ $command = "restart" ]]
	then
		stop_ce
		start_ce $confDir

	elif [[ $command =~ "status" ]]
	then
		status_ce $command

	else
		echo "Command must be one of: 'start', 'stop', 'restart' or '(ml)status'"
		return 2
	fi
}
