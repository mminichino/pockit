#!/bin/sh
#
function print_usage {
   echo "Usage: $0 -s SID [ -c schema_count -b slob_dir ]"
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
SCHEMACOUNT=8
SLOB_BIN=$HOME/SLOB

while getopts "s:c:n:b:" opt
do
  case $opt in
    s)
      ORACLE_SID=$OPTARG
      export ORACLE_SID
      ;;
    c)
      SCHEMACOUNT=$OPTARG
      ;;
    b)
      [ ! -f $OPTARG/slob.sql ] && err_exit "SLOB not found at $OPTARG"
      SLOB_BIN=$OPTARG
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

echo "ORACLE HOME   = $ORACLE_HOME"
echo "ORACLE BASE   = $ORACLE_BASE"
echo "ORACLE SID    = $ORACLE_SID"

echo "Running benchmark ... "

sed -i -e "s/SCALE=.*/SCALE=10000/" $SLOB_BIN/slob.conf
sed -i -e "s/DATABASE_STATISTICS_TYPE=.*/DATABASE_STATISTICS_TYPE=awr/" $SLOB_BIN/slob.conf

export SYSDBA_PASSWD=$PASSWORD
cd $SLOB_BIN || err_exit "Can not access SLOB directory $SLOB_BIN"
./runit.sh $SCHEMACOUNT | sed -e "s/$PASSWORD/********/"

echo "Done."

echo -n "Saving test results ... "
mkdir $POCKITDIR/SLOB_Results_$DATE
cd $SLOB_BIN || err_exit "Can not access SLOB directory $SLOB_BIN"
mv awr.txt awr_rac.txt awr_rac.html vmstat.out iostat.out mpstat.out $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/tm.out ] && rm $SLOB_BIN/tm.out
echo "Done."
