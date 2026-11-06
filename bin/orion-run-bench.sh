#!/bin/bash

function print_usage {
   echo "Usage: $0 -d directory"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "[!] Error: $1"
   else
      print_usage
   fi
   exit 1
}

WORKDIR=""

[ -n "$ORACLE_HOME" ] && [ -x "$ORACLE_HOME/bin/orion" ] || err_exit "Orion not found. Set ORACLE_HOME to a Database 19.3 or newer home that includes bin/orion."

if [ "$(id -u)" -eq 0 ]
then
   err_exit "This script must be run as the oracle user."
fi

DATE=$(date +%m%d%y_%H%M)
POCBINDIR=$(cd "$(dirname "$0")" && pwd)
POCKITDIR=$(echo "$POCBINDIR" | sed -n -e 's/^\(.*\)\/bin$/\1/p')
[ -n "$POCKITDIR" ] || err_exit "Cannot determine pockit directory from $POCBINDIR"
mkdir -p "$POCKITDIR/log" "$POCKITDIR/orion"
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

[ -n "$WORKDIR" ] && [ -d "$WORKDIR" ] && [ -w "$WORKDIR" ] || err_exit "A writable working directory is required."

cd "$POCKITDIR/orion" || err_exit "Cannot change to $POCKITDIR/orion"

TESTFILE="$WORKDIR/orion.file"
echo "ORACLE HOME    = $ORACLE_HOME"
echo "TEST DIRECTORY = $WORKDIR"
echo "LOG FILE       = $LOGFILE"
echo ""
echo "Running benchmark ... "
echo -n "Creating test file ... "
dd if=/dev/zero of="$TESTFILE" bs=65536 count=16384 >> "$LOGFILE" 2>&1
[ $? -ne 0 ] && err_exit "creating $TESTFILE"
echo "Done."

echo "$TESTFILE" > orion_large.lun
echo "$TESTFILE" > orion_small.lun

echo "Starting large I/O run ..."
"$ORACLE_HOME/bin/orion" -run advanced -testname orion_large -matrix col -num_small 0 -hugenotneeded >> "$LOGFILE" 2>&1
[ $? -ne 0 ] && err_exit "Orion large I/O run failed. See $LOGFILE"

echo "Starting small I/O run ..."
"$ORACLE_HOME/bin/orion" -run advanced -testname orion_small -matrix row -num_large 0 -hugenotneeded >> "$LOGFILE" 2>&1
[ $? -ne 0 ] && err_exit "Orion small I/O run failed. See $LOGFILE"
echo "Done."

echo -n "Cleaning up..."
rm -f orion_large.lun orion_small.lun "$TESTFILE"
echo "Done."

echo -n "Saving test results ... "
mkdir -p "$POCKITDIR/Orion_Results_$DATE"
shopt -s nullglob
results=(orion_large_* orion_small_*)
if [ "${#results[@]}" -eq 0 ]; then
   err_exit "Orion did not write result files in $POCKITDIR/orion"
fi
mv "${results[@]}" "$POCKITDIR/Orion_Results_$DATE/"
echo "Done."
