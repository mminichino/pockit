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
OTHEROPTS=""

while getopts "s:p:n:b:h:" opt
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
    h)
      OTHEROPTS="-hcccompress"
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

if [ -n "$PDB_NAME" ]; then
pdbConId=`sqlplus -S $connectString as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   alter session set nls_comp = linguistic ;
   alter session set nls_sort = binary_ci ;
   select con_id from v\\$containers where name = '$PDB_NAME' ;
   exit;
EOF`
if [ $? -ne 0 ]; then
   echo $pdbConId
   err_exit "Error getting ID for PDB $PDB_NAME"
fi
if [ -z "$pdbConId" ]; then
   err_exit "PDB $PDB_NAME does not exist in instance $ORACLE_SID"
fi
else
ISCDB=`sqlplus -S $connectString as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   select name from v\\$containers where con_id = 0;
   exit;
EOF`
if [ $? -ne 0 ]; then
   echo $ISCDB
   err_exit "Error getting CDB status"
fi
if [ -z "$ISCDB" ]; then
   pdbConId=1
else
   pdbConId=0
fi
fi

sysDataFile=`sqlplus -S $connectString as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   select name from v\\$datafile where ts# = 0 and con_id = $pdbConId ;
   exit;
EOF`

if [ $? -ne 0 ]; then
   echo $sysDataFile
   err_exit "Error connecing to SID $ORACLE_SID"
fi

dataFilePath=$(dirname $sysDataFile)

POCBINDIR=$(cd $(dirname $0) && pwd)
POCKITDIR=$(echo $POCBINDIR | sed -n -e 's/^\(.*\)\/bin$/\1/p')

if [ -n "$PDB_NAME" ]; then
   SERVICE_NAME=$PDB_NAME
else
   SERVICE_NAME=$ORACLE_SID
fi

SH_PASSWORD="$(openssl rand -base64 8 | sed -e 's/[+/=]/#/g')0"
cp $POCKITDIR/config/shconfig.template $POCKITDIR/config/${SERVICE_NAME}-olap.xml
sed -i -e "s|###PASSWORD###|$SH_PASSWORD|g" $POCKITDIR/config/${SERVICE_NAME}-olap.xml

cd $SWB_BIN
./shwizard -create -scale $SCALE -cs //$TNSHOST/$SERVICE_NAME -dbap "$PASSWORD" -ts SH -tc 16 -nopart -bigfile -allindexes $OTHEROPTS -u sh -p "$SH_PASSWORD" -cl -df $dataFilePath/sh.dbf
