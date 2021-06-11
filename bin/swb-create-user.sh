#!/bin/sh
#
function print_usage {
   echo "Usage: $0 -s SID -p -n tnshost"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "$1"
   else
      print_usage
   fi
   exit 1
}

TNSHOST=localhost
PDB_NAME=""
SWB_BIN=$HOME/swingbench/bin

while getopts "s:p:n:b:" opt
do
  case $opt in
    s)
      ORACLE_SID=$OPTARG
      ;;
    p)
      PDB_NAME=$OPTARG
      ;;
    n)
      TNSHOST=$OPTARG
      ;;
    b)
      [ ! -x $SWB_BIN/oewizard ] && err_exit "Swingbench not found at $OPTARG (oewizard not found)"
      SWB_BIN=$OPTARG
      ;;
    \?)
      print_usage
      exit 1
      ;;
  esac
done

POCBINDIR=$(cd $(dirname $0) && pwd)
POCKITDIR=$(echo $POCBINDIR | sed -n -e 's/^\(.*\)\/bin$/\1/p')

if [ -z "$ORACLE_SID" ]; then
   echo "No Oracle SID is set."
   exit 1
fi

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
   echo -n "Retype Password: "
   read -s CHECK_PASSWORD
   echo ""
   if [ "$PASSWORD" != "$CHECK_PASSWORD" ]; then
      echo "Passwords do not match"
   else
      break
   fi
done

connectString=sys/${PASSWORD}@${TNSHOST}/$ORACLE_SID

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

SOE_PASSWORD=$(xmllint --xpath "//*[local-name()='Password']/text()" $POCKITDIR/config/${SERVICE_NAME}.xml)

if [ -z "$SOE_PASSWORD" ]; then
   err_exit "Can not find SOE password in config file $POCKITDIR/config/${SERVICE_NAME}.xml"
fi

sqlplus -S $connectString as sysdba << EOF
whenever sqlerror exit sql.sqlcode
whenever oserror exit
set heading off;
set pagesize 0;
set feedback off;
ALTER SESSION SET PLSQL_CCFLAGS = 'running_in_cloud:false';

CREATE USER soe IDENTIFIED BY ${SOE_PASSWORD};

GRANT CREATE SESSION TO soe;

GRANT CREATE TABLE to soe;

GRANT CREATE SEQUENCE to soe;

GRANT CREATE PROCEDURE to soe;

GRANT RESOURCE TO soe;

GRANT CREATE VIEW TO soe;

GRANT ALTER SESSION TO soe;

GRANT EXECUTE ON dbms_lock TO soe;

GRANT ANALYZE ANY DICTIONARY TO soe;

GRANT ANALYZE ANY TO soe;

GRANT ALTER SESSION TO soe;

-- Following needed for concurrent stats collection

grant select on SYS.V_\$PARAMETER to soe;

BEGIN
  \$IF not \$\$running_in_cloud \$THEN
      EXECUTE IMMEDIATE 'GRANT MANAGE SCHEDULER TO soe';
      EXECUTE IMMEDIATE 'GRANT MANAGE ANY QUEUE TO soe';
      EXECUTE IMMEDIATE 'GRANT CREATE JOB TO soe';
      \$IF DBMS_DB_VERSION.VER_LE_10_2
      \$THEN
        null;
      \$ELSIF DBMS_DB_VERSION.VER_LE_11_2
      \$THEN
        null;
      \$ELSE
            -- The Following enables concurrent stats collection on Oracle Database 12c
            EXECUTE IMMEDIATE 'GRANT ALTER SYSTEM TO soe';
            DBMS_RESOURCE_MANAGER_PRIVS.GRANT_SYSTEM_PRIVILEGE(
                GRANTEE_NAME   => 'soe',
                PRIVILEGE_NAME => 'ADMINISTER_RESOURCE_MANAGER',
                ADMIN_OPTION   => FALSE);
       \$END
   \$ELSE
      null;
   \$END
END;

-- End;
EOF

if [ $? -ne 0 ]; then
   err_exit "Error creating SOE user"
fi
