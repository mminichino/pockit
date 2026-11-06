#!/bin/bash

function print_usage {
   echo "Usage: $0 -s SID [-p pdb_name] [-n tnshost] [-c schema_count] [-r run_time] [-b slob_dir]"
}

function err_exit {
   if [ -n "$1" ]; then
      echo "[!] Error: $1"
   else
      print_usage
   fi
   exit 1
}

function sql_ok {
   local connect="$1"
   shift
   sqlplus -S -L "$connect" "$@" <<EOF >/dev/null
whenever sqlerror exit sql.sqlcode
whenever oserror exit failure
select 1 from dual;
exit
EOF
}

function set_slob_conf {
   local key="$1"
   local value="$2"
   local file="$SLOB_BIN/slob.conf"
   local tmp
   tmp=$(mktemp)
   awk -v key="$key" -v value="$value" '
      BEGIN { found=0 }
      {
         line=$0
         sub(/^[ \t]+/, "", line)
         split(line, parts, "=")
         name=parts[1]
         sub(/^#/, "", name)
         if (name == key) {
            print key "=" value
            found=1
            next
         }
         print
      }
      END { if (!found) print key "=" value }
   ' "$file" > "$tmp" && mv "$tmp" "$file"
}

function comment_slob_keys {
   local file="$1"
   shift
   local tmp
   tmp=$(mktemp)
   awk -v keys="$*" '
      BEGIN { n=split(keys, names, " "); for (i=1; i<=n; i++) skip[names[i]]=1 }
      {
         line=$0
         sub(/^[ \t]+/, "", line)
         split(line, parts, "=")
         name=parts[1]
         if (skip[name]) {
            print "#" $0
            next
         }
         print
      }
   ' "$file" > "$tmp" && mv "$tmp" "$file"
}

function restore_slob_conf {
   if [ -n "$SLOB_CONF_BACKUP" ] && [ -f "$SLOB_CONF_BACKUP" ]; then
      cp "$SLOB_CONF_BACKUP" "$SLOB_BIN/slob.conf"
      set_slob_conf DATABASE_STATISTICS_TYPE awr
      if [ "$RUNTIME" != "300" ]; then
         set_slob_conf RUN_TIME "$RUNTIME"
      fi
   fi
}

function patch_slob_19c {
   local setup="$SLOB_BIN/setup.sh"
   local tmp
   if grep -qF 'GRANT CONNECT TO $user IDENTIFIED BY $user;' "$setup"; then
      [ -f "${setup}.pre-19c" ] || cp "$setup" "${setup}.pre-19c"
      tmp=$(mktemp)
      awk '
         index($0, "GRANT CONNECT TO $user IDENTIFIED BY $user;") {
            print "CREATE USER $user IDENTIFIED BY $user;"
            print "GRANT CONNECT TO $user;"
            next
         }
         { print }
      ' "$setup" > "$tmp" && mv "$tmp" "$setup"
      chmod +x "$setup"
   fi
}

if ! command -v sqlplus >/dev/null 2>&1
then
   err_exit "sqlplus not found."
fi

if [ "$(id -u)" -eq 0 ]
then
   err_exit "This script must be run as the oracle user."
fi

DATE=$(date +%m%d%y_%H%M)
ORACLE_SID=pocdb
export ORACLE_SID
POCBINDIR=$(cd "$(dirname "$0")" && pwd)
POCKITDIR=$(echo "$POCBINDIR" | sed -n -e 's/^\(.*\)\/bin$/\1/p')
[ -n "$POCKITDIR" ] || err_exit "Cannot determine pockit directory from $POCBINDIR"
mkdir -p "$POCKITDIR/log"
LOGFILE=$POCKITDIR/log/sloblog.$DATE
SCHEMACOUNT=8
RUNTIME=300
SLOB_BIN=$HOME/SLOB
TNSHOST=localhost
PDB_NAME=""
SLOB_CONF_BACKUP=""
trap restore_slob_conf EXIT

while getopts "b:s:c:r:n:p:" opt
do
  case $opt in
    s)
      ORACLE_SID=$OPTARG
      export ORACLE_SID
      ;;
    b)
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
      ;;
    \?)
      err_exit
      ;;
  esac
done

[[ "$SCHEMACOUNT" =~ ^[0-9]+$ ]] || err_exit "schema count must be an integer"
[[ "$RUNTIME" =~ ^[0-9]+$ ]] || err_exit "run time must be an integer number of seconds"
[ -f "$SLOB_BIN/slob.sql" ] || err_exit "SLOB not found at $SLOB_BIN"
[ -f "$SLOB_BIN/setup.sh" ] || err_exit "SLOB setup.sh not found at $SLOB_BIN"
[ -f "$SLOB_BIN/slob.conf" ] || err_exit "SLOB slob.conf not found at $SLOB_BIN"

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
   connectString="sys/${PASSWORD}@${TNSHOST}/${ORACLE_SID}"
   if sql_ok "$connectString" as sysdba; then
      break
   fi
   echo "Password is incorrect, try again..."
done

if [ -n "$PDB_NAME" ]; then
pdbConId=$(sqlplus -S "$connectString" as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   alter session set nls_comp = linguistic ;
   alter session set nls_sort = binary_ci ;
   select con_id from v\$containers where name = '$PDB_NAME' ;
   exit;
EOF
)
if [ $? -ne 0 ]; then
   echo "$pdbConId"
   err_exit "getting ID for PDB $PDB_NAME"
fi
pdbConId=$(echo "$pdbConId" | tr -d '[:space:]')
[ -n "$pdbConId" ] || err_exit "PDB $PDB_NAME does not exist in instance $ORACLE_SID"
else
ISCDB=$(sqlplus -S "$connectString" as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   select name from v\$containers where con_id = 0;
   exit;
EOF
)
if [ $? -ne 0 ]; then
   echo "$ISCDB"
   err_exit "getting CDB status"
fi
if [ -z "$(echo "$ISCDB" | tr -d '[:space:]')" ]; then
   pdbConId=1
else
   pdbConId=0
fi
fi

sysDataFile=$(sqlplus -S "$connectString" as sysdba << EOF
   whenever sqlerror exit sql.sqlcode
   whenever oserror exit
   set heading off;
   set pagesize 0;
   set feedback off;
   select name from v\$datafile where ts# = 0 and con_id = $pdbConId ;
   exit;
EOF
)

if [ $? -ne 0 ]; then
   echo "$sysDataFile"
   err_exit "connecting to SID $ORACLE_SID"
fi
sysDataFile=$(echo "$sysDataFile" | tr -d '[:space:]')
[ -n "$sysDataFile" ] || err_exit "locating the SYSTEM datafile for $ORACLE_SID"
dataFilePath=$(dirname "$sysDataFile")

if [ "$SERVICE_NAME" != "$ORACLE_SID" ]; then
   srvConnectString="sys/${PASSWORD}@${TNSHOST}/${SERVICE_NAME}"
   sql_ok "$srvConnectString" as sysdba || err_exit "connecting to $SERVICE_NAME as SYS"
else
   srvConnectString=$connectString
fi

systemConnect="system/${PASSWORD}@${TNSHOST}/${SERVICE_NAME}"
sql_ok "$systemConnect" || err_exit "SLOB 2.5.4 administers schemas as SYSTEM. The SYSTEM password for $SERVICE_NAME does not match the SYS password."

echo "ORACLE SID    = $ORACLE_SID"
echo "SERVICE NAME  = $SERVICE_NAME"
echo "LOG FILE      = $LOGFILE"
echo "DBF DEST      = $dataFilePath"
echo ""
echo -n "Continue? (y/n) [y]: "
read ANSWER
if [ "$ANSWER" = "n" ]; then
   echo "Aborting."
   exit 1
fi

echo -n "Building wait kit..."
cd "$SLOB_BIN/wait_kit" || err_exit "Cannot access SLOB directory $SLOB_BIN"
make >> "$LOGFILE" 2>&1
[ $? -ne 0 ] && err_exit "Cannot build wait kit."
echo "Done."

echo -n "Creating tablespace ... "
sqlplus -S "$srvConnectString" as sysdba <<EOF >> "$LOGFILE"
whenever sqlerror continue
drop tablespace IOPS including contents and datafiles;
whenever sqlerror exit sql.sqlcode
create bigfile tablespace IOPS datafile '${dataFilePath}/iops.dbf' size 1G
nologging online permanent extent management local autoallocate segment space management auto;
alter tablespace IOPS autoextend on next 200m maxsize unlimited;
exit
EOF
[ $? -ne 0 ] && err_exit "creating the IOPS tablespace. See $LOGFILE"
echo "Done."

echo -n "Setting up schema ... "
patch_slob_19c
SLOB_CONF_BACKUP=$SLOB_BIN/slob.conf.backup
cp "$SLOB_BIN/slob.conf" "$SLOB_CONF_BACKUP"
set_slob_conf DATABASE_STATISTICS_TYPE awr
if [ "$RUNTIME" != "300" ]; then
   set_slob_conf RUN_TIME "$RUNTIME"
fi
comment_slob_keys "$SLOB_BIN/slob.conf" ADMIN_SQLNET_SERVICE SQLNET_SERVICE_BASE SQLNET_SERVICE_MAX DBA_PRIV_USER SYSDBA_PASSWD
export DBA_PRIV_USER=system
export SYSDBA_PASSWD="$PASSWORD"
export ADMIN_SQLNET_SERVICE="//${TNSHOST}/${SERVICE_NAME}"
export SQLNET_SERVICE_BASE="//${TNSHOST}/${SERVICE_NAME}"
unset SQLNET_SERVICE_MAX

cd "$SLOB_BIN" || err_exit "Cannot access SLOB directory $SLOB_BIN"
./setup.sh IOPS "$SCHEMACOUNT" 2>&1 | awk -v p="$PASSWORD" '{ gsub(p, "********"); print }' >> "$LOGFILE"
[ "${PIPESTATUS[0]}" -ne 0 ] && err_exit "SLOB setup.sh failed. See $LOGFILE"
echo "Done."

echo -n "Running procedure ... "
userConnect="user1/user1@${TNSHOST}/${SERVICE_NAME}"
sql_ok "$userConnect" || err_exit "connecting to $SERVICE_NAME as user1"
cd "$SLOB_BIN/misc" || err_exit "Cannot access SLOB directory $SLOB_BIN"
sqlplus -S "$userConnect" <<EOF >> "$LOGFILE"
@procedure
EOF
[ $? -ne 0 ] && err_exit "installing the SLOB procedure"
echo "Done."

echo -n "Cleaning up ... "
rm -f "$SLOB_BIN/grant.out" "$SLOB_BIN/drop_users.sql" "$SLOB_BIN/drop_table.out" \
   "$SLOB_BIN/cr_tab_and_load.out" "$SLOB_BIN/tm.out"
echo "Done."
