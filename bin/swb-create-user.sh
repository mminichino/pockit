#!/bin/bash

function print_usage {
   echo "Usage: $0 -s SID [-p pdb_name] [-n tnshost] [-t tablespace]"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "[!] Error: $1"
   else
      print_usage
   fi
   exit 1
}

TNSHOST=localhost
PDB_NAME=""
ORACLE_TS=SOE

while getopts "s:p:n:t:" opt
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
    t)
      ORACLE_TS=$OPTARG
      ;;
    \?)
      err_exit
      ;;
  esac
done

command -v sqlplus >/dev/null 2>&1 || err_exit "sqlplus is required, please make sure it is installed and in PATH"
[ -n "$ORACLE_SID" ] || err_exit "No Oracle SID is set."

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

connectString="sys/${PASSWORD}@${TNSHOST}/${SERVICE_NAME}"

sqlplus -S "$connectString" as sysdba << EOF
whenever sqlerror exit sql.sqlcode
whenever oserror exit
set heading off;
set pagesize 0;
set feedback off;

CREATE USER soe IDENTIFIED BY ${PASSWORD};

ALTER USER soe DEFAULT TABLESPACE ${ORACLE_TS} QUOTA UNLIMITED ON ${ORACLE_TS};

GRANT CREATE SESSION TO soe;

GRANT CREATE TABLE to soe;

GRANT CREATE SEQUENCE to soe;

GRANT CREATE PROCEDURE to soe;

GRANT RESOURCE TO soe;

GRANT CREATE VIEW TO soe;

GRANT ALTER SESSION TO soe;

GRANT EXECUTE ON dbms_lock TO soe;

GRANT EXECUTE ON DBMS_MONITOR TO soe;

GRANT ANALYZE ANY DICTIONARY TO soe;

GRANT ANALYZE ANY TO soe;

grant select on SYS.V_\$PARAMETER to soe;

GRANT MANAGE SCHEDULER TO soe;
GRANT MANAGE ANY QUEUE TO soe;
GRANT CREATE JOB TO soe;
GRANT ALTER SYSTEM TO soe;

BEGIN
   DBMS_RESOURCE_MANAGER_PRIVS.GRANT_SYSTEM_PRIVILEGE(
       GRANTEE_NAME   => 'soe',
       PRIVILEGE_NAME => 'ADMINISTER_RESOURCE_MANAGER',
       ADMIN_OPTION   => FALSE);
END;
/
EOF

if [ $? -ne 0 ]; then
   err_exit "creating SOE user"
fi
