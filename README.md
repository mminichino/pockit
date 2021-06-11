# pockit
Oracle Database POC KIT

Steps to run:

1) Create the database.

Note -
For swingbench:
Scale   Temp Size
1     = 640M
10    = 6400M
100   = 64G
1000  = 640G

2) Run one of the create scripts such as swb-create-schema.sh (OLTP), swb-create-schema-olap.sh (OLAP), 
   or slob-create-schema.sh (OLTP) script to setup the test.

3) Run the test with the associated run script such as swb-run-bench.sh, swb-run-bench-olap.sh,
   or slob-run-bench.sh

4) Use the delete and clean scripts to remove the test schemas as needed.
