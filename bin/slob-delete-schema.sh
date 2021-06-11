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

while getopts "s:" opt
do
  case $opt in
    s)
      ORACLE_SID=$OPTARG
      export ORACLE_SID
      ;;
    n)
      TNSHOST=$OPTARG
      ;;
    \?)
      err_exit
      ;;
  esac
done

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

echo "Deleting tablespace IOPS"
echo "WARNING: This operation is destructive and can not be undone."
echo -n "Enter Oracle SID to contine: "
read ANSWER

if [ "$ANSWER" != "$ORACLE_SID" ]; then
   echo ""
   echo "Aborting ..."
   exit 1
fi

connectString=sys/${PASSWORD}@${TNSHOST}/$ORACLE_SID

echo "ORACLE HOME   = $ORACLE_HOME"
echo "ORACLE BASE   = $ORACLE_BASE"
echo "ORACLE SID    = $ORACLE_SID"
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
