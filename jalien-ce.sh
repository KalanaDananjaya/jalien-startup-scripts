#!/bin/bash

# export X509_USER_PROXY=
# export ALICE_LOGDIR= #e.g ~/ALICE/alien-logs
# export JALIEN_PATH= #e.g ~/jalien (remove if running from CVMfS)


function run_ce() {
    command=$1
    logDir=${ALICE_LOGDIR-"${HOME}/ALICE/alien-logs"}
    jalienPath=${2-"${HOME}/.jalien"}
    
    if [[ $command = "start" ]]
    then
        echo "Starting JAliEn CE"
        nohup "$jalienPath/jalien" ComputingElement > "$logDir/CE.log" 2>"$logDir/CE.err" & 
        echo $! > "$logDir/CE.pid" 
    elif [[ $command = "stop" ]]
    then
        echo "Stopping JAliEn CE"
        pkill -f alien.site.ComputingElement
    elif [[ $command = "status" ]]
    then
    if ps -p $(cat $logDir/CE.pid) > /dev/null 2>&1
    then
        echo "JAliEn CE is running"
    else
        echo "JAliEn CE is NOT running!"
    fi 
    else 
        echo "Command must be one of: 'start', 'stop' or 'status'" 
    fi
}