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

function template(){
  src_file=$1
  dest_file=$2
  changes=$3
  add=$4
  # Create backup of the original file if it exists
  [ -f $dest_file ] && cp -f $dest_file "$dest_file.orig"
  cp $src_file $dest_file
  # Apply changes
  for i in "${!changes[@]}"
    do
      echo "key  : $i"
      echo "value: ${changes[$i]}"
      echo "s|$i|${changes[$i]}|" $dest_file
      sed -i "s|$i|${changes[$i]}|" $dest_file
      echo ""
  done
  echo "$dest_file"

  for ((i = 0; i < ${#add[@]}; i++))
    do
      echo "${add[$i]}" >> $dest_file
  done

}

function setup() {
    farmHome=$1;
    user=${USER} || ${LOGNAME};
    #logdir = logdir from ldap/MonAlisa <=== [LOGDIR]=$HOME/ALICE/alien-logs
    lcgSite = 0;

    if [ ! -d $farmHome ]; then
        mkdir -p $farmHome;
    fi

    farmName=$2
    siteName=$2
    lcgSite=0
      if [[ ! $farmName = LCG* ]];
      then
          $farmName=$siteName.$1;
          lcgSite = 1;
      fi

    ALIEN_ROOT="/home/kalana/ALICE" #>>>>>Remove later Should come from the enviroment variable
    mlHome="$ALIEN_ROOT/AliEn";
    javaHome="$ALIEN_ROOT/java/MonaLisa/java"

    # ===================================================================================
    # ml_env config generation

    shouldUpdate="${monalisa_config[SHOULD_UPDATE]:-"true"}"  
    javaOpts="${monalisa_config[JAVAOPTS]:-"-Xms256m -Xmx256m"}"

    add=();
    rmv=();
    declare -A changes
    changes["^#MONALISA_USER=.*"]="MONALISA_USER=\"$user\""
    changes["^JAVA_HOME=.*"]="JAVA_HOME=\"$javaHome\""
    changes["^SHOULD_UPDATE=.*"]="SHOULD_UPDATE=\"$shouldUpdate\""
    changes["^MonaLisa_HOME=.*"]="MonaLisa_HOME=\"$mlHome\""
    changes["^FARM_HOME=.*"]="FARM_HOME=\"$farmHome\""
    changes["^#FARM_NAME=.*"]="FARM_NAME=\"$farmName\""
    changes["^#JAVA_OPTS=.*"]="JAVA_OPTS=\"$javaOpts\""

	  template "$mlHome/ml_env" " $farmHome/ml_env" $changes $add

    # ===================================================================================
    # site_env config generation

    add=();
    rmv=();
    changes=();

     # first, populate the environment with all known env variables
    env_vars=$(env)
    # TODO: This returns a BASH_FUNC_module%%= at the end which needs to be removed
    echo "$env_vars"
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
    add+=("export ALIEN_LOGDIR=$base_config[LOG_DIR]");
    add+=("export ALIEN_TMPDIR=$base_config[TMP_DIR]");
    add+=("export ALIEN_CACHEDIR=$base_config[CACHE_DIR]");
    
    if (( "$lcgSite" == 1 ));
    then
      lcg_state="/bin/true"
    else
      lcg_state="/bin/false"
    fi
    add+=("export LCG_SITE=$lcg_state");

    echo "=====================Add Props==================="
    for ((i = 0; i < ${#add[@]}; i++))
      do
          echo "${add[$i]}"
    done

    template "$mlHome/site_env" "$farmHome/site_env" $changes $add
    # ===================================================================================

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

  log_dir=${base_config[LOGDIR]}
  farmHome="$log_dir/MonaLisa"
  setup $farmHome $siteName 
#fi


echo "=====================Monalisa Config==================="
for x in "${!monalisa_config[@]}"; do printf "[%s]=%s\n" "$x" "${monalisa_config[$x]}" ; done

# echo "=====================Monalisa Props==================="
# for item in ${monalisa_properties[*]}
# do
#     printf "   %s\n" $item
# done

