#!/bin/bash

function print_usage {
   echo "Usage: $0 -s SID [-p pdb_name] [-n tnshost] [-b swingbench_dir] [-h]"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "[!] Error: $1"
   else
      print_usage
   fi
   exit 1
}

SCALE=1
TNSHOST=localhost
PDB_NAME=""
SWB_DIR=$HOME/swingbench
OTHEROPTS=""

while getopts "s:p:n:b:h" opt
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
      SWB_DIR=$OPTARG
      ;;
    h)
      OTHEROPTS="-hcccompress"
      ;;
    \?)
      err_exit
      ;;
  esac
done

[ -n "$ORACLE_SID" ] || err_exit "No Oracle SID is set."
[ -x "$SWB_DIR/bin/shwizard" ] || err_exit "Swingbench not found at $SWB_DIR (bin/shwizard not found)"

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

connectString="sys/${PASSWORD}@${TNSHOST}/${ORACLE_SID}"

if [ -n "$PDB_NAME" ]; then
pdbConId=$(sqlplus -S "$connectString" as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   alter session set nls_comp = linguistic ;
   alter session set nls_sort = binary_ci ;
   select con_id from v\$containers where name = '$PDB_NAME' ;
   exit;
EOF
)
if [ $? -ne 0 ]; then
   echo "$pdbConId"
   err_exit "getting ID for PDB $PDB_NAME"
fi
pdbConId=$(echo "$pdbConId" | tr -d '[:space:]')
[ -n "$pdbConId" ] || err_exit "PDB $PDB_NAME does not exist in instance $ORACLE_SID"
else
ISCDB=$(sqlplus -S "$connectString" as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   select name from v\$containers where con_id = 0;
   exit;
EOF
)
if [ $? -ne 0 ]; then
   echo "$ISCDB"
   err_exit "getting CDB status"
fi
if [ -z "$(echo "$ISCDB" | tr -d '[:space:]')" ]; then
   pdbConId=1
else
   pdbConId=0
fi
fi

sysDataFile=$(sqlplus -S "$connectString" as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   select name from v\$datafile where ts# = 0 and con_id = $pdbConId ;
   exit;
EOF
)

if [ $? -ne 0 ]; then
   echo "$sysDataFile"
   err_exit "connecting to SID $ORACLE_SID"
fi

sysDataFile=$(echo "$sysDataFile" | tr -d '[:space:]')
[ -n "$sysDataFile" ] || err_exit "locating the SYSTEM datafile for $ORACLE_SID"
dataFilePath=$(dirname "$sysDataFile")

if [ -n "$PDB_NAME" ]; then
   SERVICE_NAME=$PDB_NAME
else
   SERVICE_NAME=$ORACLE_SID
fi

cd "$SWB_DIR/bin" || err_exit "Cannot change to $SWB_DIR/bin"
# shellcheck disable=SC2086
./shwizard -create -scale "$SCALE" -cs "//${TNSHOST}/${SERVICE_NAME}" -dbap "$PASSWORD" -ts SH -tc 16 -nopart -bigfile -allindexes $OTHEROPTS -u sh -p "$PASSWORD" -cl -df "$dataFilePath/sh.dbf"
