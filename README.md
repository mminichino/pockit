# pockit

Oracle Database POC kit for Swingbench, SLOB, and Orion. The scripts expect Oracle Database 19.3 or newer and `sqlplus` on `PATH`. Each script prompts for the SYS password.

Swingbench defaults to `$HOME/swingbench`. SLOB defaults to `$HOME/SLOB`. Pass `-b` to point at a different install. Pass `-n` when the database is not on `localhost`. For a PDB, create and delete scripts take the CDB SID with `-s` and the PDB name with `-p`. Run scripts take the service name with `-s`.

## Swingbench

Order Entry uses `configs/SOE_Client_Side.xml`. Sales History uses `configs/Sales_History.xml`. The SOE and SH users are created with the SYS password. Schema scale is 1.

Temp space for larger Order Entry scales:

| Scale | Temp size |
| --- | --- |
| 1 | 640M |
| 10 | 6400M |
| 100 | 64G |
| 1000 | 640G |

Order Entry:

```bash
bin/swb-create-schema.sh -s ORCLCDB -p ORCLPDB1 -n dbhost
bin/swb-run-bench.sh -s ORCLPDB1 -n dbhost -r 0:10 -u 8
bin/swb-delete-schema.sh -s ORCLCDB -p ORCLPDB1 -n dbhost
```

Sales History. Add `-h` on create to load with HCC compression:

```bash
bin/swb-create-schema-olap.sh -s ORCLCDB -p ORCLPDB1 -n dbhost -h
bin/swb-run-bench-olap.sh -s ORCLPDB1 -n dbhost -r 0:10 -u 8
bin/swb-delete-schema-olap.sh -s ORCLCDB -p ORCLPDB1 -n dbhost
```

`-r` is `hh:mm`. The default run is 1 minute and 4 users. Results and the AWR report are written to `SWB_Results_<date>/`.

Non-CDB, local listener:

```bash
bin/swb-create-schema.sh -s ORCL
bin/swb-run-bench.sh -s ORCL -r 0:30 -u 16
```

Recreate the SOE user, or bring its tablespace online, after the data files are already in place:

```bash
bin/swb-create-user.sh -s ORCLCDB -p ORCLPDB1 -n dbhost
bin/swb-online-ts.sh -s ORCLCDB -p ORCLPDB1 -n dbhost -t SOE
```

`swb-drop-ts.sh` drops a tablespace and its data files. It asks you to type the SID before it continues.

## SLOB

SLOB 2.5.4. Run these as the Oracle software owner. SLOB connects its admin session as `SYSTEM`, so that password must match the SYS password. Schema users remain `user1`/`user1` and so on. The create script stores the run length and `DATABASE_STATISTICS_TYPE=awr` in `slob.conf`. `SCALE` is left as set in that file (the 2.5.4 default is `80M`).

```bash
bin/slob-create-schema.sh -s ORCLCDB -p ORCLPDB1 -n dbhost -c 8 -r 300
bin/slob-run-bench.sh -s ORCLCDB -p ORCLPDB1 -n dbhost -c 8
bin/slob-delete-schema.sh -s ORCLCDB -p ORCLPDB1 -n dbhost
```

`-c` is the number of schemas (default 8). `-r` is the run length in seconds (default 300) and is applied by the create script. Results are written to `SLOB_Results_<date>/`.

## Orion

Set `ORACLE_HOME` to a 19.3 or newer home that includes `bin/orion`. Run as the Oracle software owner. `-d` is a writable directory for the test file.

```bash
bin/orion-run-bench.sh -d /u01/orion
```

The script runs a large-I/O pass and a small-I/O pass. Results are written to `Orion_Results_<date>/`.
