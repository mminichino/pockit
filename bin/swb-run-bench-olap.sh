#!/bin/bash

function print_usage {
   echo "Usage: $0 -s service_name [-r run_time] [-u user_count] [-n tnshost] [-b swingbench_dir]"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "[!] Error: $1"
   else
      print_usage
   fi
   exit 1
}

if ! command -v sqlplus >/dev/null 2>&1
then
   err_exit "sqlplus not found."
fi

RUNTIME=0:1
USERCOUNT=4
TNSHOST=localhost
PDBFLAG=0
SWB_DIR=$HOME/swingbench

while getopts "s:r:u:n:b:" opt
do
  case $opt in
    s)
      SERVICE_NAME=$OPTARG
      ;;
    r)
      RUNTIME=$OPTARG
      ;;
    u)
      USERCOUNT=$OPTARG
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

[ -n "$SERVICE_NAME" ] || err_exit "No service name is set."
[ -x "$SWB_DIR/bin/charbench" ] || err_exit "Swingbench not found at $SWB_DIR (bin/charbench not found)"
[ -f "$SWB_DIR/configs/Sales_History.xml" ] || err_exit "Swingbench config not found at $SWB_DIR/configs/Sales_History.xml"

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

DATE=$(date +%m%d%y_%H%M)
POCBINDIR=$(cd "$(dirname "$0")" && pwd)
POCKITDIR=$(echo "$POCBINDIR" | sed -n -e 's/^\(.*\)\/bin$/\1/p')
[ -n "$POCKITDIR" ] || err_exit "Cannot determine pockit directory from $POCBINDIR"
mkdir -p "$POCKITDIR/log"
LOGFILE=$POCKITDIR/log/swblog.$DATE

mkdir "$POCKITDIR/SWB_Results_$DATE"

conId=$(sqlplus -S "$connectString" as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   alter session set nls_comp = linguistic ;
   alter session set nls_sort = binary_ci ;
   select con_id from v\$containers where name = '$SERVICE_NAME' ;
   exit;
EOF
)
if [ $? -ne 0 ]; then
   echo "$conId"
   err_exit "getting container status"
fi
conId=$(echo "$conId" | tr -d '[:space:]')
[[ "$conId" =~ ^[0-9]+$ ]] || err_exit "getting container status for $SERVICE_NAME"

if [ "$conId" -gt 1 ]; then
   PDBFLAG=1
fi

sqlplus -S "$connectString" as sysdba <<EOF >> "$LOGFILE"
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT
EOF

cd "$SWB_DIR/bin" || err_exit "Cannot change to $SWB_DIR/bin"
./charbench -cs "//${TNSHOST}/${SERVICE_NAME}" -c "$SWB_DIR/configs/Sales_History.xml" -p "$PASSWORD" -r "$POCKITDIR/SWB_Results_$DATE/results.xml" -rt "$RUNTIME" -uc "$USERCOUNT" -a -v users,tpm,tps,errs

if [ "$PDBFLAG" -eq 0 ]; then

sqlplus -S "$connectString" as sysdba <<EOF >> "$LOGFILE"
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT
variable bsnap number
variable esnap number
begin
select max(SNAP_ID)-1 into :bsnap from dba_hist_snapshot;
select max(SNAP_ID) into :esnap from dba_hist_snapshot;
end;
/
define  begin_snap   = :bsnap;
define  end_snap     = :esnap;
define  num_days     = 1;
define  report_type  = 'html';
define  report_name  = '$POCKITDIR/SWB_Results_$DATE/swb_sh_awr.html';
@?/rdbms/admin/awrrpt
EOF

else

sqlplus -S "$connectString" as sysdba <<EOF >> "$LOGFILE"
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT
variable bsnap number
variable esnap number
begin
select max(SNAP_ID)-1 into :bsnap from awr_pdb_snapshot;
select max(SNAP_ID) into :esnap from awr_pdb_snapshot;
end;
/
define  begin_snap   = :bsnap;
define  end_snap     = :esnap;
define  num_days     = 1;
define  report_type  = 'html';
define  awr_location = 'AWR_PDB';
define  report_name  = '$POCKITDIR/SWB_Results_$DATE/swb_sh_awr.html';
@?/rdbms/admin/awrrpt
EOF

fi
