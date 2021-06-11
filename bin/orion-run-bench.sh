#!/bin/sh
#

function print_usage {
   echo "Usage: $0 -d directory"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "$1"
   else
      print_usage
   fi
   exit 1
}

WORKDIR=""

if [ -z "$ORACLE_HOME" -o  ! -x "$ORACLE_HOME/bin/sqlplus" ]
then
   echo "ORACLE_HOME is not properly set."
   exit 1
fi

if [ ! -x "$ORACLE_HOME/bin/orion" ]
then
   echo "Orion not found."
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
POCBINDIR=$(cd $(dirname $0) && pwd)
POCKITDIR=$(echo $POCBINDIR | sed -n -e 's/^\(.*\)\/bin$/\1/p')
LOGFILE=$POCKITDIR/log/orionlog.$DATE

while getopts "d:" opt
do
  case $opt in
    d)
      WORKDIR=$OPTARG
      ;;
    \?)
      err_exit
      ;;
  esac
done

if [ -z "$WORKDIR" -o ! -d "$WORKDIR" ]
then
   echo "A writable working directory is required."
   exit 1
fi

[ ! -d $POCKITDIR/orion ] && mkdir $POCKITDIR/orion

cd $POCKITDIR/orion || err_exit "Can not change to $POCKITDIR/orion"

echo "ORACLE HOME    = $ORACLE_HOME"
echo "ORACLE BASE    = $ORACLE_BASE"
echo "TEST DIRECTORY = $WORKDIR"
echo ""
echo "Running benchmark ... "
echo -n "Creating test file ... "
dd if=/dev/zero of=/$WORKDIR/orion.file bs=65536 count=16384
echo "Done."

echo /$WORKDIR/orion.file > orion.lun

echo "Starting Orion run ..."
$ORACLE_HOME/bin/orion -run advanced -matrix col -num_small 0 -hugenotneeded
$ORACLE_HOME/bin/orion -run advanced -matrix row -num_large 0 -hugenotneeded
echo "Done."

echo -n "Cleaning up..."
rm orion.lun
rm /$WORKDIR/orion.file
echo "Done."

echo -n "Saving test results ... "
mkdir $POCKITDIR/Orion_Results_$DATE
mv orion_*.txt orion_*.csv $POCKITDIR/Orion_Results_$DATE
echo "Done."
