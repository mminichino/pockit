#!/bin/bash

function print_usage {
   echo "Usage: $0 -s SID [-p pdb_name] [-n tnshost] [-t tablespace]"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "[!] Error: $1"
   else
      print_usage
   fi
   exit 1
}

TNSHOST=localhost
PDB_NAME=""
ORACLE_TS=SOE

while getopts "s:p:n:t:" opt
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
    \?)
      err_exit
      ;;
  esac
done

command -v sqlplus >/dev/null 2>&1 || err_exit "sqlplus is required, please make sure it is installed and in PATH"
[ -n "$ORACLE_SID" ] || err_exit "No Oracle SID is set."

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

connectString="sys/${PASSWORD}@${TNSHOST}/${SERVICE_NAME}"

testConnection=$(sqlplus -S "$connectString" as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   select instance_name from v\$instance ;
   exit;
EOF
)
if [ $? -ne 0 ]; then
   echo "$testConnection"
   err_exit "connecting to service $SERVICE_NAME"
fi

echo "Deleting tablespace $ORACLE_TS"
echo "WARNING: This operation is destructive and can not be undone."
echo -n "Enter Oracle SID to continue: "
read ANSWER

if [ "$ANSWER" != "$ORACLE_SID" ]; then
   echo ""
   echo "Aborting ..."
   exit 1
fi

sqlplus -S "$connectString" as sysdba << EOF
whenever sqlerror exit sql.sqlcode
whenever oserror exit
set heading off;
set pagesize 0;
set feedback off;
alter tablespace $ORACLE_TS offline immediate ;
drop tablespace $ORACLE_TS including contents and datafiles ;
EOF

if [ $? -ne 0 ]; then
   err_exit "dropping tablespace $ORACLE_TS"
fi
