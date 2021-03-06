#!/bin/bash

# Starting script for VoBox
# v0.1
# kwijethu@cern.ch


ldapHostname="alice-ldap.cern.ch"
ldapPort="8389"
hostname=`hostname -f`

source ./jalien-ce.sh
source ./monalisa.sh

set -e

if [[ $1 = "monalisa" ]]
    then
        run_monalisa $2 $ldapHostname $ldapPort $hostname

    elif [[ $1 = "ce" ]]
    then
        run_ce $2
        
    elif [[ $1 = "help" ]]
    then
        echo "jalien-vobox <Command> <Service>"
        echo "<Command> is one of: 'start', 'stop', 'restart', 'status', 'mlstatus', 'systemd'"
	    echo "<Service> is one of: ce, monalisa (defaulting to both if not specified)"

    else 
        run_monalisa $2 $ldapHostname $ldapPort $hostname
        run_ce $2
        
fi
