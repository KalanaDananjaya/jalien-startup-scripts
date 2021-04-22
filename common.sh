#!/bin/bash

# Starting script for VoBox
# v0.1
# kwijethu@cern.ch


ldapHostname="alice-ldap.cern.ch"
ldapPort="8389"
hostname="voboxalice8.cern.ch"
farmHome="/home/kalana/MonaLisa" # MonAlisa package extracted location

source ./jalien-ce.sh
source ./monalisa.sh

if [[ $1 = "monalisa" ]]
    then
        run_monalisa $2 $ldapHostname $ldapPort $hostname $farmHome

    elif [[ $1 = "ce" ]]
    then
        run_ce $2
        
    elif [[ $1 = "help" ]]
    then
        echo "jalien-vobox <Command> <Service>"
        echo "<Command> is one of: 'start', 'stop', 'restart', 'status', 'mlstatus', 'systemd'"
	    echo "<Service> is one of: CE, MonaLisa (defaulting to both if not specified)"
    else 
        run_monalisa $2 $ldapHostname $ldapPort $hostname $farmHome 
        run_ce $2
fi
