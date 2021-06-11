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

TNSHOST=localhost
PDB_NAME=""
SWB_BIN=$HOME/swingbench/bin
ORACLE_TS=soe

while getopts "s:p:n:b:t:" opt
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
    t)
      ORACLE_TS=$OPTARG
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

POCBINDIR=$(cd $(dirname $0) && pwd)
POCKITDIR=$(echo $POCBINDIR | sed -n -e 's/^\(.*\)\/bin$/\1/p')

if [ -z "$ORACLE_SID" ]; then
   echo "No Oracle SID is set."
   exit 1
fi

if [ -n "$PDB_NAME" ]; then
   SERVICE_NAME=$PDB_NAME
else
   SERVICE_NAME=$ORACLE_SID
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

echo "Deleting tablespace $ORACLE_TS"
echo "WARNING: This operation is destructive and can not be undone."
echo -n "Enter Oracle SID to contine: "
read ANSWER

if [ "$ANSWER" != "$ORACLE_SID" ]; then
   echo ""
   echo "Aborting ..."
   exit 1
fi

sqlplus -S $connectString as sysdba << EOF
whenever sqlerror exit sql.sqlcode
whenever oserror exit
set heading off;
set pagesize 0;
set feedback off;
alter tablespace $ORACLE_TS offline immediate ;
drop tablespace $ORACLE_TS including contents and datafiles ;
EOF

if [ $? -ne 0 ]; then
   err_exit "Error dropping tablespace $ORACLE_TS"
fi
