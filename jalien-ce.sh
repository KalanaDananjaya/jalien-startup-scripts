#!/bin/bash

# Starting script for CE
# v0.1
# kwijethu@cern.ch

function run_ce() {
    command=$1
    confDir=$2
    
    logDir=${ALICE_LOGDIR-"${HOME}/ALICE/alien-logs"}/CE
    envFile="$logDir/CE-env.sh"
    pidFile="$logDir/CE.pid"
    mkdir -p $logDir || { echo "Unable to create log directory at $logDir" && return; }

    ceConf="$confDir/CE.conf"
    ceEnv="$confDir/CE.env"
    envCommand="/cvmfs/alice.cern.ch/bin/alienv printenv JAliEn"
    className=alien.site.ComputingElement

    if [[ $command = "start" ]]
    then
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

    elif [[ $command = "stop" ]]
    then
		echo "Stopping JAliEn CE"
		pkill -f $className

    elif [[ $command = "status" ]]
    then
		if (ps -p $(cat $pidFile) -fww | fgrep $className) > /dev/null 2>&1
		then
			echo "JAliEn CE is running"
			return 0
		else
			echo "JAliEn CE is NOT running"
			return 1
		fi

    else
	echo "Command must be one of: 'start', 'stop' or 'status'"
	return 2
    fi
}
