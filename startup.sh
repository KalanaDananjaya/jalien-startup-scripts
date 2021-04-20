#!/bin/bash

# Starting script for ML
# v0.1
# kwijethu@cern.ch

hostname="voboxalice8.cern.ch"
ldapHostname="alice-ldap.cern.ch"
ldapPort="8389"


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
  echo ""
  
  # Append new Lines
  echo ">>> Adding new lines"
  for i in "${add[@]}"
  do
    echo "+++ $i"
    echo "$i" >> $destFile
  done
  echo ""

  # Remove existing lines
  echo ">>> Removing existing lines"
  for i in "${rmv[@]}"
  do
    # Find exact word matches and delete the line
    echo "--- $i"
    sed -i "/$i\b/d" $destFile
  done
  echo ""

  echo " --- Templating Complete ---"
  echo ""
  
}

function setup() {
    farmHome=$1;
    logDir=$2

    # ===================================================================================
    # myFarm.conf 

    add=();
    rmv=();
    unset $changes
    declare -Ag changes

    add+=(${siteConfiguration[MONALISA_ADDMODULES_LIST]}); #TODO : find a site with "addModules” key and test

    cp -r "$farmHome/Service/myFarm/" "$logDir/MonaLisa/myFarm/"
    template "$farmHome/Service/myFarm/myFarm.conf" "$logDir/MonaLisa/myFarm/myFarm.conf"

    # ===================================================================================
    # ml.properties

    add=();
    rmv=();
    unset $changes
    declare -Ag changes

    for key in "${monalisaProperties[@]}"
    do 
        add+=($key)
    done


    location=${monalisaConfiguration[LOCATION]} || ${monalisaConfiguration[SITE_LOCATION]} || ""
    country=${monalisaConfiguration[COUNTRY]} || ${monalisaConfiguration[SITE_COUNTRY]} || ""
    long=${monalisaConfiguration[LONGITUDE]} || ${monalisaConfiguration[SITE_LONGITUDE]} || "N/A"
    lat=${monalisaConfiguration[LATITUDE]} || ${monalisaConfiguration[SITE_LATITUDE]} || "N/A"

    changes["^MonaLisa.Location.*"]="MonaLisa.Location=$location"
    changes["^MonaLisa.Country.*"]="MonaLisa.Country=$country"
    changes["^MonaLisa.LAT.*"]="MonaLisa.LAT=$lat"
    changes["^MonaLisa.LONG.*"]="MonaLisa.LONG=$long"

    template "$farmHome/Service/myFarm/ml.properties" "$logDir/MonaLisa/myFarm/ml.properties"

    # ============================= Export JAVA OPTS =======================================
    export "JAVAOPTS=${monalisaConfiguration[JAVAOPTS]}"

    # ===================================================================================
}


# wget http://alimonitor.cern.ch/download/MonaLisa/MonaLisa-<version>.tar.gz` 
# unpack

siteLDAPQuery=$(ldapsearch -x -h $ldapHostname -p $ldapPort -b "host=$hostname,ou=Config,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch")

declare -A siteConfiguration
#TODO: There are 2 objectClass keys
while IFS= read -r line; do
#Ignore empty,commented and unwanted lines and create an associative array from ldap
if [[ ! $line = \#* ]] && [[ ! -z $line ]] && [[ ! $line = search* ]] && [[ ! $line = result* ]];
    then
    key=$(echo $line| cut -d ":" -f 1 | xargs )
    val=$(echo $line | cut -d ":" -f 2- | xargs)
    val=$(envsubst <<< $val)
    siteConfiguration[${key^^}]=$val
fi
done <<< "$siteLDAPQuery"


siteName=${siteConfiguration[MONALISA]}
monalisaLDAPQuery=$(ldapsearch -x -h $ldapHostname -p $ldapPort -b "name=$siteName,ou=MonaLisa,ou=Services,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch")

declare -A monalisaConfiguration
monalisaProperties=()
#TODO: There are 2 objectClass keys, can dn breaks at wrong point
while IFS= read -r line; do
#Ignore empty, commented and unwanted lines and create an associative array from ldap
if [[ ! $line = \#* ]] && [[ ! -z $line ]] && [[ ! $line = search* ]] && [[ ! $line = result* ]];
    then
    # Create a new array for addProperties
    if [[ $line = addProperties* ]];
    then
        val=$(echo $line | cut -d ":" -f 2- | xargs)
        monalisaProperties+=($val)
    else
        key=$(echo $line | cut -d ":" -f 1 | xargs)
        val=$(echo $line | cut -d ":" -f 2- | xargs)
        monalisaConfiguration[${key^^}]=$val
    fi
fi
done <<< "$monalisaLDAPQuery"

echo "===================== Base Config ==================="
for x in "${!siteConfiguration[@]}"; do printf "[%s]=%s\n" "$x" "${siteConfiguration[$x]}" ; done
echo ""

echo "===================== MonAlisa Properties ==================="
for x in "${monalisaProperties[@]}"; do printf  "$x\n"  ; done
echo ""

echo "===================== MonAlisa Config ==================="
for x in "${!monalisaConfiguration[@]}"; do printf "[%s]=%s\n" "$x" "${monalisaConfiguration[$x]}" ; done
echo ""

farmHome="/home/kalana/MonaLisa" # MonAlisa package extracted location
logDir=${siteConfiguration[LOGDIR]}   #   should be added at deployment
setup $farmHome $logDir