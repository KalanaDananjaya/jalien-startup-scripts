#!/bin/bash

function template(){
  src_file=$1
  dest_file=$2
  changes=$3
  [ -f $dest_file ] && cp -f $dest_file "$dest_file.orig"
  cp $src_file $dest_file
  for i in "${!changes[@]}"
  do
    echo "key  : $i"
    echo "value: ${changes[$i]}"
    echo "s|$i|${changes[$i]}|" $dest_file
    sed -i "s|$i|${changes[$i]}|" $dest_file
    echo ""
  done
  echo "$dest_file"
}

function setup() {
    farmHome=$1;
    user=${USER} || ${LOGNAME};
    #logdir = logdir from ldap/MonAlisa === [LOGDIR]=$HOME/ALICE/alien-logs
    # $lcgSite = 0;

    if [ ! -d $farmHome ]; then
        mkdir -p $farmHome;
    fi

    farmName=$2
   # siteName=$2

    # if($farmName =~ /^LCG(.*)/){
    #     $farmName = $siteName.$1;
    #     $lcgSite = 1;
    # }

    ALIEN_ROOT="/home/kalana/ALICE" #>>>>>Remove later Should come from the enviroment variable
    mlHome="${ALIEN_ROOT}/AliEn";
    javaHome="${ALIEN_ROOT}/java/MonaLisa/java"
  
    shouldUpdate="${monalisa_config[SHOULD_UPDATE]:-"true"}"  
    javaOpts="${monalisa_config[JAVAOPTS]:-"-Xms256m -Xmx256m"}"

    declare -A changes
    changes["^#MONALISA_USER=.*"]="MONALISA_USER=\"$user\""
    changes["^JAVA_HOME=.*"]="JAVA_HOME=\"$javaHome\""
    changes["^SHOULD_UPDATE=.*"]="SHOULD_UPDATE=\"$shouldUpdate\""
    changes["^MonaLisa_HOME=.*"]="MonaLisa_HOME=\"$mlHome\""
    changes["^FARM_HOME=.*"]="FARM_HOME=\"$farmHome\""
    changes["^#FARM_NAME=.*"]="FARM_NAME=\"$farmName\""
    changes["^#JAVA_OPTS=.*"]="JAVA_OPTS=\"$javaOpts\""

	  template "$mlHome/ml_env" " $farmHome/ml_env"
}

ldap_hostname="alice-ldap.cern.ch"
ldap_port="8389"
ldap=$(ldapsearch -x -h $ldap_hostname -p $ldap_port -b "host=voboxalice8.cern.ch,ou=Config,ou=CERN,ou=Sites,o=alice,dc=cern,dc=ch")


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

  #echo "site name issssssssssss $siteName"
  log_dir=${base_config[LOGDIR]}
  farmHome="$log_dir/MonaLisa"
  setup $farmHome $siteName 
#fi


echo "=====================Monalisa Config==================="
for x in "${!monalisa_config[@]}"; do printf "[%s]=%s\n" "$x" "${monalisa_config[$x]}" ; done

echo "=====================Monalisa Props==================="
for item in ${monalisa_properties[*]}
do
    printf "   %s\n" $item
done

