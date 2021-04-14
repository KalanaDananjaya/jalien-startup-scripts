#!/bin/bash

# Starting script for ML
# v0.1
# kwijethu@cern.ch

hostname="voboxalice8.cern.ch"
ldap_hostname="alice-ldap.cern.ch"
ldap_port="8389"

# function getEnvVarsFromFile {
#     file=$1;
#     vars=$2;

#     if(open(OUT, "(source $file ; for k in @vars ; ".'do echo "$k=${!k}"; done) 2>/dev/null |')){
#     my $line;
#     while($line = <OUT>){
#         if($line && $line =~ /\s*(.*)\s*=\s*(.*)\s*$/ && $2){
#           $ENV{$1} = $2;
#         }
#     }
#     close(OUT);
#       }else{
#     print "Failed opening $file to get '@vars' variables. Using defaults...\n";
#       }
# }


#Check if the current key exist in the array and if not push a default value
function pushIfNoKey(){
  keyVal=$1
  key=$(echo $keyVal| cut -d "=" -f 1 | xargs )
  present=false

  for currentKey in "${!add[@]}"
  do
    # if [[  "$currentKey" == "$key" ]]; then
    if [[  "$currentKey" =~ /^$key\s*=\s*(.*)$/ ]]; then
      $present=true
    fi
  done

  if [[ "$present" == false ]]; then
    add+=($keyVal)
  fi
}

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
    user=${USER} || ${LOGNAME};
    logdir=$3
    ALIEN_ROOT=$4
    lcgSite=0;


    if [ ! -d $farmHome ]; then
        mkdir -p $farmHome;
    fi

    farmName=$2
    siteName=$2
    lcgSite=0
      if [[ ! $farmName = LCG* ]];
      then
          $farmName=$siteName.$1;
          lcgSite=1;
      fi

    if [ -z "$ALIEN_ROOT" ]
      then
        echo "Please setup the environment variable ALIEN_ROOT before running the script"
        exit 1
      else
        mlHome="$ALIEN_ROOT/AliEn";
        javaHome="$ALIEN_ROOT/java/MonaLisa/java"

        # ===================================================================================
        # ml_env config 

        shouldUpdate="${monalisa_config[SHOULD_UPDATE]:-"true"}"  
        javaOpts="${monalisa_config[JAVAOPTS]:-"-Xms256m -Xmx256m"}"

        add=();
        rmv=();
        declare -Ag changes;

        changes["^#MONALISA_USER=.*"]="MONALISA_USER=\"$user\""
        changes["^JAVA_HOME=.*"]="JAVA_HOME=\"$javaHome\""
        changes["^SHOULD_UPDATE=.*"]="SHOULD_UPDATE=\"$shouldUpdate\""
        changes["^MonaLisa_HOME=.*"]="MonaLisa_HOME=\"$mlHome\""
        changes["^FARM_HOME=.*"]="FARM_HOME=\"$farmHome\""
        changes["^#FARM_NAME=.*"]="FARM_NAME=\"$farmName\""
        changes["^#JAVA_OPTS=.*"]="JAVA_OPTS=\"$javaOpts\""

        template "$mlHome/ml_env" "$farmHome/ml_env"

        # ===================================================================================
        # site_env config 

        add=();
        rmv=();
        unset changes;

        # first, populate the environment with all known env variables
        env_vars=$(env)
        # TODO: This returns a BASH_FUNC_module%%= at the end which needs to be removed
        #echo "$env_vars"
        while IFS= read -r line; do
          #Ignore empty lines and earlier defined variables
          if [[ ! -z $line ]] && [[  ! $line = JAVA_HOME*||JAVA_OPTS*||FARM_NAME*||MonaLisa_HOME*||SHOULD_UPDATE*||MONALISA_USER* ]];
            then
              key=$(echo $line| cut -d "=" -f 1 | xargs )
              val=$(echo $line | cut -d "=" -f 2- | xargs)
              val=$(envsubst <<< $val)
              add+=("export $key=$val")
          fi
        done <<< "$env_vars"

        # getEnvVarsFromFile("$farmHome/ml_env", "URL_LIST_UPDATE"); #TODO

        # add+=("export URL_LIST_UPDATE=${URL_LIST_UPDATE}"); #TODO
        add+=("export MonaLisa_HOME=$mlHome");
        add+=("export FARM_HOME=$farmHome");
        add+=("export ALIEN_LOGDIR=$logdir");
        add+=("export ALIEN_TMPDIR=$base_config[TMP_DIR]");
        add+=("export ALIEN_CACHEDIR=$base_config[CACHE_DIR]");
        
        if (( "$lcgSite" == 1 ));
        then
          lcg_state="/bin/true"
        else
          lcg_state="/bin/false"
        fi
        add+=("export LCG_SITE=$lcg_state");

        template "$mlHome/site_env" "$farmHome/site_env"
        
        # ===================================================================================
        # myFarm.conf 

        add=();
        rmv=();
        unset $changes
        declare -Ag changes

        add+=(${base_config[MONALISA_ADDMODULES_LIST]});
        rmv+=(${base_config[MONALISA_REMOVEMODULES_LIST]});
      
        if (( "$lcgSite" == 1 ));
        then
          # for LCG sites, also run this
          add+=("#Status of the LCG services")
          add+=('*LCGServicesStatus{monStatusCmd, localhost, "$ALIEN_ROOT/bin/alien -x $ALIEN_ROOT/java/MonaLisa/AliEn/lcg_vobox_services,timeout=800"}%900')
          add+=("#JobAgent LCG Status - from Stefano - reports using ApMon; output of last run in checkJAStatus.log")
          add+=('*JA_LCGStatus{monStatusCmd, localhost, "$ALIEN_ROOT/bin/alien -x $ALIEN_ROOT/scripts/lcg/checkJAStatus.pl -s 0 >checkJAStatus.log 2>&1,timeout=800"}%1800')
        fi
        
        add+=('*IPs{monIPAddresses, localhost, ""}%900');
        add+=('*MonaLisa_MemInfo{MemInfo, localhost, ""}%60');
        add+=('*MonaLisa_DiskDF{DiskDF, localhost, ""}%300');
        add+=('*MonaLisa_SysInfo{SysInfo, localhost, ""}%900');
        add+=('*MonaLisa_NetworkConfiguration{NetworkConfiguration, localhost, ""}%900');
        add+=('*ContainerSupport{monStatusCmd, localhost, "/cvmfs/alice.cern.ch/containers/bin/status.sh"}%300');
        
        changes["^>localhost"]=">$fqdn"
        template "$mlHome/myFarm.conf" "$farmHome/myFarm.conf"

        # ===================================================================================
        # ml.properties

        add=();
        rmv=();
        unset $changes
        declare -Ag changes

        group=${monalisa_config[MONALISA_GROUP]} || "alice"
        lus=${monalisa_config[MONALISA_LUS]} || "monalisa.cacr.caltech.edu,monalisa.cern.ch"
        location=${monalisa_config[MONALISA_LOCATION]} || ${monalisa_config[SITE_LOCATION]} || ""
        country=${monalisa_config[MONALISA_COUNTRY]} || ${monalisa_config[SITE_COUNTRY]} || ""
        long=${monalisa_config[MONALISA_LONGITUDE]} || ${monalisa_config[SITE_LONGITUDE]} || "N/A"
        lat=${monalisa_config[MONALISA_LATITUDE]} || ${monalisa_config[SITE_LATITUDE]} || "N/A"
        admin=${monalisa_config[MONALISA_ADMINISTRATOR_LIST]} || ${monalisa_config[SITE_ADMINISTRATOR_LIST]}

        # ITERATE ADMIN : TODO
        storeType=${monalisa_config[MONALISA_STORETYPE]} || "mem"

        add+=(${monalisa_config[MONALISA_ADDPROPERTIES_LIST]})

        # logging properties
        pushIfNoKey "lia.Monitor.Farm.Conf.ConfVerifier.level=WARNING"
        #   pushIfNoKey "lia.Monitor.Filters.AliEnFilter.level=FINEST"

        # monXDRUDP properties
        pushIfNoKey "lia.Monitor.modules.GenericUDPListener.SO_RCVBUF_SIZE=2097152"
        pushIfNoKey "lia.Monitor.modules.monXDRUDP.MONITOR_SENDERS=true"
        pushIfNoKey "lia.Monitor.modules.monXDRUDP.SENDER_EXPIRE_TIME=600"

        # AliEnFilter properties
        pushIfNoKey "lia.Monitor.Store.FileLogger.maxDays=0"
        pushIfNoKey "lia.Monitor.Filters.AliEnFilter=true"
        pushIfNoKey "lia.Monitor.Filters.AliEnFilter.SLEEP_TIME=120"
        pushIfNoKey "lia.Monitor.Filters.AliEnFilter.PARAM_EXPIRE=900"
        pushIfNoKey "lia.Monitor.Filters.AliEnFilter.ZOMBIE_EXPIRE=14400"
        pushIfNoKey "lia.Monitor.Filters.AliEnFilter.LDAP_QUERY_INTERVAL=7200"
        pushIfNoKey "lia.Monitor.Filters.AliEnFilter.RUN_JOB_SYNC_SCRIPT=false"
        pushIfNoKey "lia.Monitor.Filters.AliEnFilter.JOB_SYNC_RUN_INTERVAL=7200"
        pushIfNoKey "lia.Monitor.Filters.AliEnFilter.JOB_SYNC_SCRIPT_TIMEOUT=1200"


        rmv+=(${monalisa_config[MONALISA_REMOVEPROPERTIES_LIST]})

        # changes["^MonaLisa.ContactName.*"]="MonaLisa.ContactName=".join(",", @contact) #TODO
        # changes["^MonaLisa.ContactEmail.*"]="MonaLisa.ContactEmail=".join(",", @email) #TODO
        changes["^MonaLisa.Location.*"]="MonaLisa.Location=$location"
        changes["^MonaLisa.Country.*"]="MonaLisa.Country=$country"
        changes["^MonaLisa.LAT.*"]="MonaLisa.LAT=$lat"
        changes["^MonaLisa.LONG.*"]="MonaLisa.LONG=$long"
        changes["^lia.Monitor.LUSs.*"]="lia.Monitor.LUSs=$lus"
        changes["^lia.Monitor.group.*"]="lia.Monitor.group=$group"

        if [[ $storeType =~ ^mem* ]]
        then
          changes["^lia.Monitor.Store.TransparentStoreFast.web_writes.*"]="lia.Monitor.Store.TransparentStoreFast.web_writes=0";
          changes["^lia.Monitor.use_emysqldb.*"]="lia.Monitor.use_emysqldb=false"
          changes["^lia.Monitor.use_epgsqldb.*"]="lia.Monitor.use_epgsqldb=false"
          add+=("lia.Monitor.memory_store_only=true")
          rmv+=("lia.Monitor.jdbcDriverString\\s*=\\s*com.mckoi.JDBCDriver")
          rmv+=("lia.Monitor.jdbcDriverString\\s*=\\s*com.mysql.jdbc.Driver")
        elif [[ $storeType =~ ^mysql ]]
        then
          changes["^lia.Monitor.Store.TransparentStoreFast.web_writes.*"]="lia.Monitor.Store.TransparentStoreFast.web_writes=3"
          changes["^#?\\s*lia.Monitor.use_emysqldb.*"]="lia.Monitor.use_emysqldb=true"
          changes["^lia.Monitor.use_epgsqldb.*"]="lia.Monitor.use_epgsqldb=false"
          rmv+=("lia.Monitor.memory_store_only\\s*=\\s*true")
          rmv+=("lia.Monitor.jdbcDriverString\\s*=\\s*com.mckoi.JDBCDriver")
          rmv+=("lia.Monitor.jdbcDriverString\\s*=\\s*com.mysql.jdbc.Driver")
        elif [[ $storeType =~ ^pgsql ]]
        then
          changes["^lia.Monitor.Store.TransparentStoreFast.web_writes.*"]="lia.Monitor.Store.TransparentStoreFast.web_writes=3"
          changes["^#?\\s*lia.Monitor.use_epgsqldb.*"]="lia.Monitor.use_epgsqldb=true"
          changes["^lia.Monitor.use_emysqldb.*"]="lia.Monitor.use_emysqldb=false"
          rmv+=("lia.Monitor.memory_store_only\\s*=\\s*true")
          rmv+=("lia.Monitor.jdbcDriverString\\s*=\\s*com.mckoi.JDBCDriver")
          rmv+=("lia.Monitor.jdbcDriverString\\s*=\\s*com.mysql.jdbc.Driver")
        fi

        template "$mlHome/AliEn/ml.properties" "$farmHome/ml.properties"

        

        # from the @$add list, check if the user has changed the $logDir, i.e. the java.util.logging.FileHandler.pattern property
        present=false
        key="java.util.logging.FileHandler.pattern"
        for currentKey in "${!add[@]}"
        do
        
          if [[  "$currentKey" =~ /^$key\s*=\s*(.*)$/ ]]; then
            $present=true
            logFile=
          fi
        done
        logFile = getValueForKey($add, );
    $logDir = $1 if (defined($logFile) && $logFile =~ /(.*)\/ML\%g.log/);

        # ===================================================================================
        # db.conf.embedded 

        add=();
        rmv=();
        unset $changes

        template "$mlHome/db.conf.embedded" "$farmHome/db.conf.embedded"
    fi

    

}

ldap=$(ldapsearch -x -h $ldap_hostname -p $ldap_port -b "host=$hostname,ou=Config,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch")


#if [ -z $ldap];
#  then

  declare -A base_config
  #TODO: There are 2 objectClass keys
  while IFS= read -r line; do
    #Ignore empty,commented and unwanted lines and create an associative array from ldap
    if [[ ! $line = \#* ]] && [[ ! -z $line ]] && [[ ! $line = search* ]] && [[ ! $line = result* ]];
      then
        key=$(echo $line| cut -d ":" -f 1 | xargs )
        val=$(echo $line | cut -d ":" -f 2- | xargs)
        val=$(envsubst <<< $val)
        base_config[${key^^}]=$val
    fi
  done <<< "$ldap"

  echo "=====================Base Config==================="
  for x in "${!base_config[@]}"; do printf "[%s]=%s\n" "$x" "${base_config[$x]}" ; done
  echo ""

  siteName=${base_config[MONALISA]}
  ldap_mon=$(ldapsearch -x -h $ldap_hostname -p $ldap_port -b "name=$siteName,ou=MonaLisa,ou=Services,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch")

  declare -A monalisa_config
  monalisa_properties=()
  #TODO: There are 2 objectClass keys, can dn breaks at wrong point
  while IFS= read -r line; do
    #Ignore empty, commented and unwanted lines and create an associative array from ldap
    if [[ ! $line = \#* ]] && [[ ! -z $line ]] && [[ ! $line = search* ]] && [[ ! $line = result* ]];
      then
        # Create a new array for addProperties
        if [[ $line = addProperties* ]];
        then
          val=$(echo $line | cut -d ":" -f 2- | xargs)
          monalisa_properties+=($val)
        else
          key=$(echo $line | cut -d ":" -f 1 | xargs)
          val=$(echo $line | cut -d ":" -f 2- | xargs)
          monalisa_config[${key^^}]=$val
        fi
    fi
  done <<< "$ldap_mon"

  ALIEN_ROOT="/home/kalana/ALICE" #>>>>>Remove later Should come from the enviroment variable
  log_dir=${HOME}/ALICE/alien-logs  # ${base_config[LOGDIR]} ||  should be added at deployment
  farmHome="$log_dir/MonaLisa"
  setup $farmHome $siteName $log_dir $ALIEN_ROOT
#fi


echo "=====================Monalisa Config==================="
for x in "${!monalisa_config[@]}"; do printf "[%s]=%s\n" "$x" "${monalisa_config[$x]}" ; done

# echo "=====================Monalisa Props==================="
# for item in ${monalisa_properties[*]}
# do
#     printf "   %s\n" $item
# done

