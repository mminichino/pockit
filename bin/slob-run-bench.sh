#!/bin/bash

function print_usage {
   echo "Usage: $0 -s SID [-p pdb_name] [-n tnshost] [-c schema_count] [-b slob_dir]"
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
SLOB_BIN=$HOME/SLOB
TNSHOST=localhost
PDB_NAME=""
SLOB_CONF_BACKUP=""
trap restore_slob_conf EXIT

while getopts "s:c:n:p:b:" opt
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
      SLOB_BIN=$OPTARG
      ;;
    \?)
      err_exit
      ;;
  esac
done

[[ "$SCHEMACOUNT" =~ ^[0-9]+$ ]] || err_exit "schema count must be an integer"
[ -f "$SLOB_BIN/runit.sh" ] || err_exit "SLOB not found at $SLOB_BIN"
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
   connectString="sys/${PASSWORD}@${TNSHOST}/${SERVICE_NAME}"
   if sql_ok "$connectString" as sysdba; then
      break
   fi
   echo "Password is incorrect, try again..."
done

systemConnect="system/${PASSWORD}@${TNSHOST}/${SERVICE_NAME}"
sql_ok "$systemConnect" || err_exit "SLOB 2.5.4 administers the run as SYSTEM. The SYSTEM password for $SERVICE_NAME does not match the SYS password."

echo "ORACLE SID    = $ORACLE_SID"
echo "SERVICE NAME  = $SERVICE_NAME"
echo "LOG FILE      = $LOGFILE"
echo "Running benchmark ... "

SLOB_CONF_BACKUP=$SLOB_BIN/slob.conf.backup
cp "$SLOB_BIN/slob.conf" "$SLOB_CONF_BACKUP"
set_slob_conf DATABASE_STATISTICS_TYPE awr
comment_slob_keys "$SLOB_BIN/slob.conf" ADMIN_SQLNET_SERVICE SQLNET_SERVICE_BASE SQLNET_SERVICE_MAX DBA_PRIV_USER SYSDBA_PASSWD
export DBA_PRIV_USER=system
export SYSDBA_PASSWD="$PASSWORD"
export ADMIN_SQLNET_SERVICE="//${TNSHOST}/${SERVICE_NAME}"
export SQLNET_SERVICE_BASE="//${TNSHOST}/${SERVICE_NAME}"
unset SQLNET_SERVICE_MAX

cd "$SLOB_BIN" || err_exit "Cannot access SLOB directory $SLOB_BIN"
./runit.sh "$SCHEMACOUNT" 2>&1 | awk -v p="$PASSWORD" '{ gsub(p, "********"); print }' | tee -a "$LOGFILE"
[ "${PIPESTATUS[0]}" -ne 0 ] && err_exit "SLOB runit.sh failed. See $LOGFILE"
echo "Done."

echo -n "Saving test results ... "
mkdir -p "$POCKITDIR/SLOB_Results_$DATE"
for result in awr.txt awr_rac.txt awr_rac.html awr.html awr.html.gz awr_rac.html.gz \
   vmstat.out iostat.out mpstat.out .file_operations_audit_trail.out statspack.txt slob_debug.out
do
   [ -f "$SLOB_BIN/$result" ] && mv "$SLOB_BIN/$result" "$POCKITDIR/SLOB_Results_$DATE/"
done
rm -f "$SLOB_BIN/tm.out"
echo "Done."
