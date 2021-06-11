#!/bin/sh
#
function print_usage {
   echo "Usage: $0 -s SID -n tnshost -c schema_count -r run_time [-b slob_dir]"
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
[ -z "$1" ] && err_exit "create_connect_string: variable required."
[ -z "$2" ] && err_exit "create_connect_string: user required."
[ -z "$3" ] && err_exit "create_connect_string: password required."
[ -z "$4" ] && err_exit "create_connect_string: tnshost required."
[ -z "$5" ] && err_exit "create_connect_string: service name required."

if [ "$2" == "sys" ]; then
   extraString="as sysdba"
else
   extraString=""
fi

eval $1=\$2/\${3}@\${4}/\$5

sqlplus -S ${!1} $extraString << EOF 2>&1 > /dev/null
whenever sqlerror exit sql.sqlcode
whenever oserror exit
select count(*) from sys.dual;
EOF
if [ $? -eq 0 ]; then
   return 0
else
   return 1
fi
}

function get_password {
[ -z "$1" ] && err_exit "get_password: variable required."
[ -z "$2" ] && err_exit "get_password: user required."
[ -z "$3" ] && err_exit "get_password: tnshost required."
[ -z "$4" ] && err_exit "get_password: service name required."

while true
do
   echo -n "Password: "
   read -s PASSWORD
   echo ""
   create_connect_string $1 $2 $PASSWORD $3 $4
   if [ $? -ne 0 ]; then
      echo "Password is incorrect, try again..."
   else
      ORACLE_PWD=$PASSWORD
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
RUNTIME=300
SLOB_BIN=$HOME/SLOB
TNSHOST=localhost
PDB_NAME=""
connectString=""
srvConnectString=""
userConnectString=""
ORACLE_PWD=""

while getopts "b:s:c:r:" opt
do
  case $opt in
    s)
      ORACLE_SID=$OPTARG
      export ORACLE_SID
      ;;
    b)
      [ ! -f $OPTARG/slob.sql ] && err_exit "SLOB not found at $OPTARG"
      SLOB_BIN=$OPTARG
      ;;
    n)
      TNSHOST=$OPTARG
      ;;
    p)
      PDB_NAME=$OPTARG
      ;;
    c)
      SCHEMACOUNT=$OPTARG
      ;;
    r)
      RUNTIME=$OPTARG
      [[ $RUNTIME =~ (^[0-9]+$) ]] || err_exit $RUNTIME
      ;;
    \?)
      echo "Usage: $0 [ -p project -s SID -c schema_count -r run_time ]"
      exit 1
      ;;
  esac
done

if [ -n "$PDB_NAME" ]; then
   SERVICE_NAME=$PDB_NAME
else
   SERVICE_NAME=$ORACLE_SID
fi

get_password connectString sys $TNSHOST $ORACLE_SID

[ -z "$connectString" ] && err_exit "Error: could not create connect string."

if [ -n "$PDB_NAME" ]; then
pdbConId=`sqlplus -S $connectString as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   alter session set nls_comp = linguistic ;
   alter session set nls_sort = binary_ci ;
   select con_id from v\\$containers where name = '$PDB_NAME' ;
   exit;
EOF`
if [ $? -ne 0 ]; then
   echo $pdbConId
   err_exit "Error getting ID for PDB $PDB_NAME"
fi
if [ -z "$pdbConId" ]; then
   err_exit "PDB $PDB_NAME does not exist in instance $ORACLE_SID"
fi
else
ISCDB=`sqlplus -S $connectString as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   select name from v\\$containers where con_id = 0;
   exit;
EOF`
if [ $? -ne 0 ]; then
   echo $ISCDB
   err_exit "Error getting CDB status"
fi
if [ -z "$ISCDB" ]; then
   pdbConId=1
else
   pdbConId=0
fi
fi

sysDataFile=`sqlplus -S $connectString as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   select name from v\\$datafile where ts# = 0 and con_id = $pdbConId ;
   exit;
EOF`

if [ $? -ne 0 ]; then
   echo $sysDataFile
   err_exit "Error connecing to SID $ORACLE_SID"
fi

dataFilePath=$(dirname $sysDataFile)

echo "ORACLE HOME   = $ORACLE_HOME"
echo "ORACLE BASE   = $ORACLE_BASE"
echo "ORACLE SID    = $ORACLE_SID"
echo "SERVICE NAME  = $SERVICE_NAME"
echo "LOG FILE      = $LOGFILE"
echo "DBF DEST      = $dataFilePath"
echo ""
echo -n "Continue? (y/n) [y]: "
read ANSWER
[ "$ANSWER" == "n" ] && err_exit "Aborting."

echo -n "Building wait kit..."
cd $SLOB_BIN/wait_kit || err_exit "Can not access SLOB directory $SLOB_BIN"
make >> $LOGFILE 2>&1

[ $? -ne 0 ] && err_exit "Can not build wait kit."
echo "Done."

echo -n "Creating schema ... "

cd $SLOB_BIN || err_exit "Can not access SLOB directory $SLOB_BIN"

cp $SLOB_BIN/misc/ts.sql $SLOB_BIN/misc/tsmod.sql
sed -i -e "s:datafile size:datafile '$dataFilePath/iops.dbf' size:" $SLOB_BIN/misc/tsmod.sql

if [ "$SERVICE_NAME" != "$ORACLE_SID" ]; then
   create_connect_string srvConnectString sys $ORACLE_PWD $TNSHOST $SERVICE_NAME || err_exit "Can not connect to $SERVICE_NAME"
else
   srvConnectString=$connectString
fi
sqlplus -S $srvConnectString as sysdba <<EOF >> $LOGFILE
@./misc/tsmod.sql
EOF

echo "Done."

echo -n "Setting up schema ... "

export SYSDBA_PASSWD=$PASSWORD
export ADMIN_SQLNET_SERVICE=$SERVICE_NAME
export SQLNET_SERVICE_BASE=$SERVICE_NAME
cd $SLOB_BIN || err_exit "Can not access SLOB directory $SLOB_BIN"
./setup.sh IOPS $SCHEMACOUNT 2>&1 | sed -e "s/$PASSWORD/********/" >> $LOGFILE

echo "Done."

echo -n "Running procedure ... "
create_connect_string userConnectString user1 user1 $TNSHOST $SERVICE_NAME || err_exit "Can not connect to $SERVICE_NAME as user1"

cd $SLOB_BIN/misc || err_exit "Can not access SLOB directory $SLOB_BIN"
sqlplus -S $userConnectString <<EOF >> $LOGFILE
@procedure
EOF

echo "Done."

if [ "$RUNTIME" -ne 300 ]
then
   echo -n "Changing run time to $RUNTIME ... "
   cp $SLOB_BIN/slob.conf $SLOB_BIN/slob.conf.backup
   sed -i -e "s/RUN_TIME=.*/RUN_TIME=$RUNTIME/" $SLOB_BIN/slob.conf
   echo "Done."
fi

echo -n "Cleaning up ... "

[ -f $SLOB_BIN/grant.out ] && rm $SLOB_BIN/grant.out
[ -f $SLOB_BIN/drop_users.sql ] && rm $SLOB_BIN/drop_users.sql
[ -f $SLOB_BIN/drop_table.out ] && rm $SLOB_BIN/drop_table.out
[ -f $SLOB_BIN/cr_tab_and_load.out ] && rm $SLOB_BIN/cr_tab_and_load.out
[ -f $SLOB_BIN/tm.out ] && rm $SLOB_BIN/tm.out

echo "Done."
