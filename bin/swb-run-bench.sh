#!/bin/sh
#

if [ -z "$ORACLE_HOME" -o  ! -x "$ORACLE_HOME/bin/sqlplus" ]
then
   echo "ORACLE_HOME is not properly set."
   exit 1
fi

RUNTIME=0:1
USERCOUNT=4
TNSHOST=localhost
PDBFLAG=0
SWB_BIN=$HOME/swingbench/bin

while getopts "s:r:u:n:" opt
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
      [ ! -x $SWB_BIN/oewizard ] && err_exit "Swingbench not found at $OPTARG (oewizard not found)"
      SWB_BIN=$OPTARG
      ;;
    \?)
      echo "Usage: $0 [ -r run_time -u user_count -s service_name -n tnshost -b swingbench_bin ]"
      exit 1
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

connectString=sys/${PASSWORD}@${TNSHOST}/$SERVICE_NAME

DATE=$(date +%m%d%y_%H%M)
POCBINDIR=$(cd $(dirname $0) && pwd)
POCKITDIR=$(echo $POCBINDIR | sed -n -e 's/^\(.*\)\/bin$/\1/p')
[ ! -d $POCKITDIR/log ] && mkdir $POCKITDIR/log
LOGFILE=$POCKITDIR/log/swblog.$DATE

mkdir $POCKITDIR/SWB_Results_$DATE

conId=`sqlplus -S $connectString as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   alter session set nls_comp = linguistic ;
   alter session set nls_sort = binary_ci ;
   select con_id from v\\$containers where name = '$SERVICE_NAME' ;
   exit;
EOF`
if [ $? -ne 0 ]; then
   echo $conId
   err_exit "Error getting container status"
fi

if [ "$conId" -gt 1 ]; then
   PDBFLAG=1
fi

sqlplus -S $connectString as sysdba <<EOF >> $LOGFILE
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT
EOF

cd $SWB_BIN
./charbench -cs //$TNSHOST/$SERVICE_NAME -c $POCKITDIR/config/${SERVICE_NAME}.xml -r $POCKITDIR/SWB_Results_$DATE/results.xml -dt thin -rt $RUNTIME -uc $USERCOUNT -a -v users,tpm,tps,errs

if [ "$PDBFLAG" -eq 0 ]; then

sqlplus -S $connectString as sysdba <<EOF >> $LOGFILE
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
define  report_name  = '/$POCKITDIR/SWB_Results_$DATE/swb_soe_awr.html';
@?/rdbms/admin/awrrpt
EOF

else

sqlplus -S $connectString as sysdba <<EOF >> $LOGFILE
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
define  report_name  = '/$POCKITDIR/SWB_Results_$DATE/swb_soe_awr.html';
@?/rdbms/admin/awrrpt
EOF

fi
