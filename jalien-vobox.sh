#!/bin/bash

# Starting script for VoBox
# v0.1

ldapHostname="alice-ldap.cern.ch"
ldapPort="8389"
hostname=`hostname -f`

dir="$(cd `dirname -- "$0"` &>/dev/null && pwd)"

source $dir/jalien-ce.sh
source $dir/monalisa.sh

cmds='start status stop restart mlstatus'
svcs='ce monalisa'
confDir="${HOME}/.alien/config"

usage()
{
	exec >&2
	echo ""
	echo "Usage: jalien-vobox <Command> [<Service>]"
	echo ""
	echo "<Command> is one of: $cmds"
	echo "<Service> is one of: $svcs (defaulting to both if not specified)"
	echo ""
	exit 2
}

for cmd in $cmds
do
	[[ "$1" = $cmd ]] && break
done

[[ "$1" = $cmd ]] || usage

for svc in $svcs
do
	[[ "$2" = $svc ]] && break
done

[[ "$2" = $svc ]] || [[ "$2" = "" ]] || usage

for svc in ${2:-$svcs}
do
	if [[ $svc = "monalisa" ]]
	then
		run_monalisa $cmd $confDir $ldapHostname $ldapPort $hostname

	elif [[ $svc = "ce" ]]
	then
		run_ce $cmd $confDir $ldapHostname $ldapPort $hostname
    
	else 
		usage
	fi
done

