#!/bin/bash

# Starting script for ML
# v0.1
# kwijethu@cern.ch

# export X509_USER_PROXY=

function run_ce() {
    command=$1
    logDir=${ALICE_LOGDIR-"${HOME}/ALICE/alien-logs"}
    jalienPath=${2-"${HOME}/.jalien"}
    
    if [[ $command = "start" ]]
    then
        mkdir -p $logDir/CE || echo "Please set VoBox log directory in the LDAP and try again.." && exit 1
        echo "Starting JAliEn CE"
        nohup "$jalienPath/jalien" ComputingElement > "$logDir/CE/CE.log" 2>"$logDir/CE/CE.err" & 
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