#!/bin/sh
#
function print_usage {
   echo "Usage: $0 -s SID -n tnshost"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "$1"
   else
      print_usage
   fi
   exit 1
}

function create_connect_string {
[ -z "$1" ] && err_exit "create_connect_string: password required."
[ -z "$2" ] && err_exit "create_connect_string: tnshost required."
[ -z "$3" ] && err_exit "create_connect_string: service name required."
connectString=sys/${1}@${2}/$3
sqlplus -S $connectString as sysdba << EOF 2>&1 > /dev/null
whenever sqlerror exit sql.sqlcode
whenever oserror exit
select * from dual ;
EOF
if [ $? -eq 0 ]; then
   return 0
else
   return 1
fi
}

function get_password {
[ -z "$1" ] && err_exit "get_password: tnshost required."
[ -z "$2" ] && err_exit "get_password: service name required."

while true
do
   echo -n "Password: "
   read -s PASSWORD
   echo ""
   create_connect_string $PASSWORD $1 $2
   if [ $? -ne 0 ]; then
      echo "Password is incorrect, try again..."
   else
      break
   fi
done

}

if [ -z "$ORACLE_HOME" -o  ! -x "$ORACLE_HOME/bin/sqlplus" ]
then
   echo "ORACLE_HOME is not properly set."
   exit 1
fi

MYID=$(id -u)

if [ "$MYID" -eq 0 ]
then
   echo "This script must be run as the oracle user."
   exit 1
fi

DATE=$(date +%m%d%y_%H%M)
ORACLE_BASE=$(echo $ORACLE_HOME | sed -n -e 's/^\(.*\)\/product\/.*$/\1/p')
ORACLE_SID=pocdb
export ORACLE_SID
POCBINDIR=$(cd $(dirname $0) && pwd)
POCKITDIR=$(echo $POCBINDIR | sed -n -e 's/^\(.*\)\/bin$/\1/p')
LOGFILE=$POCKITDIR/log/sloblog.$DATE
TNSHOST=localhost
connectString=""
PDB_NAME=""

while getopts "s:" opt
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

get_password $TNSHOST $SERVICE_NAME

[ -z "$connectString" ] && err_exit "Error: could not create connect string."

echo "Deleting tablespace IOPS"
echo "WARNING: This operation is destructive and can not be undone."
echo -n "Enter Oracle SID to contine: "
read ANSWER

if [ "$ANSWER" != "$ORACLE_SID" ]; then
   echo ""
   echo "Aborting ..."
   exit 1
fi

echo "ORACLE HOME   = $ORACLE_HOME"
echo "ORACLE BASE   = $ORACLE_BASE"
echo "ORACLE SID    = $ORACLE_SID"
echo "SERVICE NAME  = $SERVICE_NAME"
echo "LOG FILE      = $LOGFILE"

echo -n "Dropping schema ... "

sqlplus -S $connectString as sysdba <<EOF >> $LOGFILE
DROP TABLESPACE IOPS INCLUDING CONTENTS AND DATAFILES;
EOF

if [ $? -ne 0 ]; then
   echo "Failed."
else
   echo "Done."
fi
