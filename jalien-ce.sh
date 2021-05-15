#!/bin/bash

# Starting script for ML
# v0.1
# kwijethu@cern.ch

function run_ce() {
    command=$1
    logDir=${ALICE_LOGDIR-"${HOME}/ALICE/alien-logs"}
    jalienConfigPath=${2-"${HOME}/.jalien/CE"}
    jalienBinPath="${HOME}/jalien"
    envCommand="/cvmfs/alice.cern.ch/bin/alienv printenv JAliEn"
    envFile="$logDir/ce-env.sh"

    if [[ $command = "start" ]]
    then
        # Read JAliEn config files
        if [[ -f "$jalienConfigPath/versions" ]]
        then
            declare -A jalienConfiguration
            while IFS= read -r line
            do
            if [[ ! $line = \#* ]] && [[ ! -z $line ]]
                then
                key=$(echo $line| cut -d "=" -f 1 | xargs )
                val=$(echo $line | cut -d "=" -f 2- | xargs)
                jalienConfiguration[${key^^}]=$val
            fi
            done <<< "$jalienConfigPath/versions"
        fi

        # Check for JAliEn package
        if [[ -v "jalienConfiguration[CLASSPATH]" ]]
        then
            echo "CLASSPATH=${jalienConfiguration[CLASSPATH]}; export CLASSPATH" >> $envFile
        fi

        # Check for JAliEn version 
        if [[ -v "jalienConfiguration[JAliEn]" ]]
        then
            envVersionCommand="$envCommand::${jalienConfiguration[JAliEn]}"
            $envVersionCommand >> $envFile
            source $envFile
        else
            $envCommand >> $envFile
            source $envFile
        fi
        
        mkdir -p $logDir/CE || { echo "Please set VoBox log directory in the LDAP and try again.." && exit 1; }
        echo "Starting JAliEn CE"
        nohup $jalienBinPath ComputingElement > "$logDir/CE/CE.log" 2>"$logDir/CE/CE.err" & 
        echo $! > "$logDir/CE/CE.pid" 

    elif [[ $command = "stop" ]]
    then
        echo "Stopping JAliEn CE"
        pkill -f alien.site.ComputingElement
    elif [[ $command = "status" ]]
    then
    if ps -p $(cat $logDir/CE/CE.pid) > /dev/null 2>&1
    then
        echo "JAliEn CE is running"
    else
        echo "JAliEn CE is NOT running!"
    fi 
    else 
        echo "Command must be one of: 'start', 'stop' or 'status'" 
    fi
}