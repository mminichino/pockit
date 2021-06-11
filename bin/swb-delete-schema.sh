#!/bin/sh
#
function print_usage {
   echo "Usage: $0 -s SID -p -n tnshost"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "$1"
   else
      print_usage
   fi
   exit 1
}

SCALE=1
TNSHOST=localhost
PDB_NAME=""
SWB_BIN=$HOME/swingbench/bin

while getopts "s:p:n:b:" opt
do
  case $opt in
    s)
      ORACLE_SID=$OPTARG
      ;;
    p)
      PDB_NAME=$OPTARG
      ;;
    n)
      TNSHOST=$OPTARG
      ;;
    b)
      [ ! -x $SWB_BIN/oewizard ] && err_exit "Swingbench not found at $OPTARG (oewizard not found)"
      SWB_BIN=$OPTARG
      ;;
    \?)
      print_usage
      exit 1
      ;;
  esac
done

if [ -z "$ORACLE_SID" ]; then
   echo "No Oracle SID is set."
   exit 1
fi

which sqlplus 2>&1 >/dev/null
if [ $? -ne 0 ]; then
   err_exit "sqlplus is required, please make sure it is installed and in PATH"
fi

which xmllint 2>&1 >/dev/null
if [ $? -ne 0 ]; then
   err_exit "xmllint is required, please make sure it is installed and in PATH"
fi

while true
do
   echo -n "Password: "
   read -s PASSWORD
   echo ""
   echo -n "Retype Password: "
   read -s CHECK_PASSWORD
   echo ""
   if [ "$PASSWORD" != "$CHECK_PASSWORD" ]; then
      echo "Passwords do not match"
   else
      break
   fi
done

connectString=sys/${PASSWORD}@${TNSHOST}/$ORACLE_SID

testConnection=`sqlplus -S $connectString as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   select instance_name from v\\$instance ;
   exit;
EOF`
if [ $? -ne 0 ]; then
   echo $testConnection
   err_exit "Can not connect to instance $ORACLE_SID"
fi

POCBINDIR=$(cd $(dirname $0) && pwd)
POCKITDIR=$(echo $POCBINDIR | sed -n -e 's/^\(.*\)\/bin$/\1/p')

if [ -n "$PDB_NAME" ]; then
   SERVICE_NAME=$PDB_NAME
else
   SERVICE_NAME=$ORACLE_SID
fi

if [ ! -f $POCKITDIR/config/${SERVICE_NAME}.xml ]; then
   err_exit "Can not find config file at $POCKITDIR/config/${SERVICE_NAME}.xml"
fi

SOE_PASSWORD=$(xmllint --xpath "//*[local-name()='Password']/text()" $POCKITDIR/config/${SERVICE_NAME}.xml)

if [ -z "$SOE_PASSWORD" ]; then
   err_exit "Can not find SOE password in config file $POCKITDIR/config/${SERVICE_NAME}.xml"
fi

cd $SWB_BIN
./oewizard -drop -scale 0.1 -cs //$TNSHOST/$SERVICE_NAME -dbap "$PASSWORD" -ts SOE -u soe -p "$SOE_PASSWORD" -cl
