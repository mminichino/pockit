#!/bin/bash

function print_usage {
   echo "Usage: $0 -s SID [-p pdb_name] [-n tnshost] [-b swingbench_dir]"
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
SWB_DIR=$HOME/swingbench

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
      SWB_DIR=$OPTARG
      ;;
    \?)
      err_exit
      ;;
  esac
done

[ -n "$ORACLE_SID" ] || err_exit "No Oracle SID is set."
command -v sqlplus >/dev/null 2>&1 || err_exit "sqlplus is required, please make sure it is installed and in PATH"
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

if [ -n "$PDB_NAME" ]; then
   SERVICE_NAME=$PDB_NAME
else
   SERVICE_NAME=$ORACLE_SID
fi

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

cd "$SWB_DIR/bin" || err_exit "Cannot change to $SWB_DIR/bin"
./shwizard -drop -scale 0.1 -cs "//${TNSHOST}/${SERVICE_NAME}" -dbap "$PASSWORD" -ts SH -u sh -p "$PASSWORD" -cl
