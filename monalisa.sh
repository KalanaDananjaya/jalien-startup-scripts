#!/bin/bash

# Starting script for ML
# v0.1
# kwijethu@cern.ch


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
  unset changes && echo ""
  
  # Append new Lines
  echo ">>> Adding new lines"
  for i in "${add[@]}"
  do
    echo "+++ $i"
    echo "$i" >> $destFile
  done
  unset add && echo ""

  # Remove existing lines
  echo ">>> Removing existing lines"
  for i in "${rmv[@]}"
  do
    # Find exact word matches and delete the line
    echo "--- $i"
    sed -i "/$i\b/d" $destFile
  done
  unset rmv && echo ""

  echo " --- Templating Complete ---"
  echo ""
  
}

function setup() {
    farmHome=$1
    logDir=$2

    add=()
    rmv=()
    declare -Ag changes

    # Copy base templates to the local directory
    mkdir -p "$logDir/MonaLisa/myFarm/"
   
    # ===================================================================================
    # myFarm.conf 

    add+=(${siteConfiguration[MONALISA_ADDMODULES_LIST]}); #TODO : find a site with "addModules” key and test
    add+=("^monLogTail{Cluster=AliEnServicesLogs,Node=CE,command=tail -n 15 -F $logDir/CE/alien.log 2>&1}%3")
    add+=("*AliEnServicesStatus{monStatusCmd, localhost, \"logDir=$logDir `dirname $0`/jalien-vobox CE mlstatus,timeout=800\"}%900")

    template "$farmHome/Service/myFarm/myFarm.conf" "$logDir/MonaLisa/myFarm/myFarm.conf"

    # ========================================================================================
    # ml.properties

    declare -Ag changes
    for key in "${monalisaProperties[@]}"
    do 
        add+=($key)
    done

    location=${monalisaConfiguration[LOCATION]-${monalisaConfiguration[SITE_LOCATION]}} || ""
    country=${monalisaConfiguration[COUNTRY]-${monalisaConfiguration[SITE_COUNTRY]}} || ""
    long=${monalisaConfiguration[LONGITUDE]-${monalisaConfiguration[SITE_LONGITUDE]}} || "N/A"
    lat=${monalisaConfiguration[LATITUDE]-${monalisaConfiguration[SITE_LATITUDE]}} || "N/A"

    changes["^MonaLisa.Location.*"]="MonaLisa.Location=$location"
    changes["^MonaLisa.Country.*"]="MonaLisa.Country=$country"
    changes["^MonaLisa.LAT.*"]="MonaLisa.LAT=$lat"
    changes["^MonaLisa.LONG.*"]="MonaLisa.LONG=$long"

    template "$farmHome/Service/myFarm/ml.properties" "$logDir/MonaLisa/myFarm/ml.properties"

    # ===================================================================================
    # ml.env
    
    declare -Ag changes
    changes["^FARM_NAME*"]="FARM_NAME=${monalisaConfiguration[NAME]}"
    changes["^#FARM_HOME*"]="FARM_HOME=$logDir/MonaLisa/myFarm"
    changes["^MONALISA_USER*"]=`MONALISA_USER=id -u -n`

    template "$farmHome/Service/CMD/ml_env" "$logDir/MonaLisa/myFarm/ml_env"

    # ============================= Export variables =====================================
    export CONFDIR="$logDir/MonaLisa/myFarm"
    export ALICE_LOGDIR=$logDir
    export JAVAOPTS=${monalisaConfiguration[JAVAOPTS]}
    # ===================================================================================
}


function run_monalisa() {

    if [[ $1 == "start" ]]
    then
        monalisaConfigPath="${HOME}/.jalien/monalisa"
        envCommand="/cvmfs/alice.cern.ch/bin/alienv printenv MonaLisa"
        farmHome=${MonaLisa_HOME} # MonaLisa package location should be defined as an environment variable
        envFile="$logDir/ml-env.sh"


        if [[ ! -z $farmHome ]]
        then
            # Read MonAlisa config files
            if [[ -f "$monalisaConfigPath/versions" ]]
            then
                declare -A monalisaConfiguration
                while IFS= read -r line
                do
                if [[ ! $line = \#* ]] && [[ ! -z $line ]]
                    then
                    key=$(echo $line| cut -d "=" -f 1 | xargs )
                    val=$(echo $line | cut -d "=" -f 2- | xargs)
                    monalisaConfiguration[${key^^}]=$val
                fi
                done <<< "$monalisaConfigPath/versions"
            fi

            # Check for MonAlisa version 
            if [[ -v "monalisaConfiguration[MonaLisa]" ]]
            then
                envVersionCommand="$envCommand::${monalisaConfiguration[MonaLisa]}"
                $envVersionCommand > $envFile
                source $envFile
            else
                $envCommand > $envFile
                source $envFile
            fi

            # ======================== Start templating config files  ========================

            ldapHostname=$2
            ldapPort=$3
            hostname=$4

            # Obtain site related configurations from LDAP
            siteLDAPQuery=$(ldapsearch -x -h $ldapHostname -p $ldapPort -b "host=$hostname,ou=Config,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch")

            declare -A siteConfiguration
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

            # Obtain MonAlisa service related configurations from LDAP
            monalisaLDAPQuery=$(ldapsearch -x -h $ldapHostname -p $ldapPort -b "name=$siteName,ou=MonaLisa,ou=Services,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch")

            declare -A monalisaConfiguration
            monalisaProperties=()
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

            echo "===================== MonaLisa Properties ==================="
            for x in "${monalisaProperties[@]}"; do printf  "$x\n"  ; done
            echo ""

            echo "===================== MonaLisa Config ==================="
            for x in "${!monalisaConfiguration[@]}"; do printf "[%s]=%s\n" "$x" "${monalisaConfiguration[$x]}" ; done
            echo ""
            
            logDir=${siteConfiguration[LOGDIR]}  

            mkdir -p "$logDir/MonaLisa" || { echo "Please set VoBox log directory in the LDAP and try again.." && exit 1; }
            echo "MonaLisa Log Directory: $logDir/MonaLisa"
            echo "Started configuring MonAlisa..."
            echo ""

            setup $farmHome $logDir          

            # Start MonaLisa
            echo "Starting MonaLisa.... Please check $logDir/ML.log for logs"
            nohup $farmHome/Service/CMD/ML_SER start &> "$logDir/ML.log"

        else
            echo "Please point MonaLisa variable to the MonaLisa package location.." && exit 1
        fi
    elif [[ $1 == "stop" ]]
    then
        echo "Stopping MonaLisa..."
        for pid in $(ps -aux | grep -i mona | awk '{print $2}')
        do
            # request children to shutdown
            kill -0 ${pid} 2>/dev/null 
        done
    fi
}




