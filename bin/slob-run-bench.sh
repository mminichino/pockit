#!/bin/sh
#
function print_usage {
   echo "Usage: $0 -s SID [ -p pdb_name -c schema_count -b slob_dir ]"
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
SCHEMACOUNT=8
SLOB_BIN=$HOME/SLOB
TNSHOST=localhost
PDB_NAME=""
connectString=""

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
    n)
      TNSHOST=$OPTARG
      ;;
    p)
      PDB_NAME=$OPTARG
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

if [ -n "$PDB_NAME" ]; then
   SERVICE_NAME=$PDB_NAME
else
   SERVICE_NAME=$ORACLE_SID
fi

get_password $TNSHOST $ORACLE_SID

[ -z "$connectString" ] && err_exit "Error: could not create connect string."

echo "ORACLE HOME   = $ORACLE_HOME"
echo "ORACLE BASE   = $ORACLE_BASE"
echo "ORACLE SID    = $ORACLE_SID"
echo "SERVICE NAME  = $SERVICE_NAME"

echo "Running benchmark ... "

cp $SLOB_BIN/slob.conf $SLOB_BIN/slob.conf.backup
sed -i -e "s/SCALE=.*/SCALE=10000/" $SLOB_BIN/slob.conf
sed -i -e "s/DATABASE_STATISTICS_TYPE=.*/DATABASE_STATISTICS_TYPE=awr/" $SLOB_BIN/slob.conf

export SYSDBA_PASSWD=$PASSWORD
export ADMIN_SQLNET_SERVICE=$SERVICE_NAME
export SQLNET_SERVICE_BASE=$SERVICE_NAME
cd $SLOB_BIN || err_exit "Can not access SLOB directory $SLOB_BIN"
./runit.sh $SCHEMACOUNT 2>&1 | sed -e "s/$PASSWORD/********/"

echo "Done."

echo -n "Saving test results ... "
mkdir $POCKITDIR/SLOB_Results_$DATE
cd $SLOB_BIN || err_exit "Can not access SLOB directory $SLOB_BIN"
[ -f $SLOB_BIN/awr.txt ] && mv awr.txt $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/awr_rac.txt ] && mv awr_rac.txt $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/awr_rac.html ] && mv awr_rac.html $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/vmstat.out ] && mv vmstat.out $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/iostat.out ] && mv iostat.out $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/mpstat.out ] && mv mpstat.out $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/.file_operations_audit_trail.out ] && mv .file_operations_audit_trail.out $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/statspack.txt ] && mv statspack.txt $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/slob_debug.out ] && mv slob_debug.out $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/awr.html.gz ] && mv awr.html.gz $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/awr_rac.html.gz ] && mv awr_rac.html.gz $POCKITDIR/SLOB_Results_$DATE
[ -f $SLOB_BIN/tm.out ] && rm $SLOB_BIN/tm.out
echo "Done."
