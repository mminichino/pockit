#!/bin/bash

function print_usage {
   echo "Usage: $0 -s SID [-p pdb_name] [-n tnshost]"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "[!] Error: $1"
   else
      print_usage
   fi
   exit 1
}

function sql_ok {
   local connect="$1"
   shift
   sqlplus -S -L "$connect" "$@" <<EOF >/dev/null
whenever sqlerror exit sql.sqlcode
whenever oserror exit failure
select 1 from dual;
exit
EOF
}

if ! command -v sqlplus >/dev/null 2>&1
then
   err_exit "sqlplus not found."
fi

if [ "$(id -u)" -eq 0 ]
then
   err_exit "This script must be run as the oracle user."
fi

DATE=$(date +%m%d%y_%H%M)
ORACLE_SID=pocdb
export ORACLE_SID
POCBINDIR=$(cd "$(dirname "$0")" && pwd)
POCKITDIR=$(echo "$POCBINDIR" | sed -n -e 's/^\(.*\)\/bin$/\1/p')
[ -n "$POCKITDIR" ] || err_exit "Cannot determine pockit directory from $POCBINDIR"
mkdir -p "$POCKITDIR/log"
LOGFILE=$POCKITDIR/log/sloblog.$DATE
TNSHOST=localhost
PDB_NAME=""

while getopts "s:p:n:" opt
do
  case $opt in
    s)
      ORACLE_SID=$OPTARG
      export ORACLE_SID
      ;;
    p)
      PDB_NAME=$OPTARG
      ;;
    n)
      TNSHOST=$OPTARG
      ;;
    \?)
      err_exit
      ;;
  esac
done

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
   connectString="sys/${PASSWORD}@${TNSHOST}/${SERVICE_NAME}"
   if sql_ok "$connectString" as sysdba; then
      break
   fi
   echo "Password is incorrect, try again..."
done

echo "Deleting tablespace IOPS"
echo "WARNING: This operation is destructive and can not be undone."
echo -n "Enter Oracle SID to continue: "
read ANSWER

if [ "$ANSWER" != "$ORACLE_SID" ]; then
   echo ""
   echo "Aborting ..."
   exit 1
fi

echo "ORACLE SID    = $ORACLE_SID"
echo "SERVICE NAME  = $SERVICE_NAME"
echo "LOG FILE      = $LOGFILE"

echo -n "Dropping schema ... "

sqlplus -S "$connectString" as sysdba <<EOF >> "$LOGFILE"
whenever sqlerror exit sql.sqlcode
DROP TABLESPACE IOPS INCLUDING CONTENTS AND DATAFILES;
EOF

if [ $? -ne 0 ]; then
   err_exit "dropping tablespace IOPS. See $LOGFILE"
fi
echo "Done."
