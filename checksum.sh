#!/usr/bin/env bash

# Perform replication integrity checksum using Percona pt-table-checksum on a 
# specific database with option for table size cutoff. Written to be used in a
# Jenkins job.
#
# Environment Variable Prerequisites
#
# DB_USER           User with privileges to perform checksum
# 
# DB_PASS           Password associated with given DB_USER
#
# DB                Which database to checksum
#
# DB_HOST           Which host is this database located
#
# TABLE_SIZE_CUTOFF Maximum size of table to be included in checksum (not counting indices), 0 to turn off

: ${DB?Please specify a database.}
: ${DB_HOST?Please specify a database host.}
: ${DB_USER?Please specify database user.}
: ${DB_PASS?Please specify a database password.}

if [ -z "$TABLE_SIZE_CUTOFF" ]; then 
    TABLE_SIZE_CUTOFF="0"
    echo "TABLE_SIZE_CUTOFF defaulted to '$TABLE_SIZE_CUTOFF'"
fi

echo [ `date` ] starting checksum of $DB on $DB_HOST

function check_table {
    pt-table-checksum h=$DB_HOST,u=$DB_USER,p=$DB_PASS --databases=$DB --tables=$1
    local status=$?
    if [ $status -ne 0 ]; then
        if [ $status -ne 255 ]; then
            echo "Error(s) found for table ($1):" >&2
            ((($status&1)>0)) && echo "A non-fatal error occurred" >&2
            ((($status&2)>0)) && echo "--pid file exists and the PID is running" >&2
            ((($status&4)>0)) && echo "Caught SIGHUP, SIGINT, SIGPIPE, or SIGTERM" >&2
            ((($status&8)>0)) && echo "No replicas or cluster nodes were found" >&2
            ((($status&16)>0)) && echo "At least one diff was found" >&2
            ((($status&32)>0)) && echo "At least one chunk was skipped" >&2
            ((($status&64)>0)) && echo "At least one table was skipped" >&2
        else
            echo "A fatal error has occurred" >&2
        fi
    fi
    return $status
}

echo "Checking for data drift on Master-Slave replication..."

TABLES_SQL="SELECT table_name, round((data_length / 1024 / 1024), 2) as size, data_length > $TABLE_SIZE_CUTOFF AND $TABLE_SIZE_CUTOFF > 0 as skip FROM information_schema.TABLES  WHERE table_schema = '$DB' order by data_length ASC"

STATUS=0
while read table_name size skip; do
    [[ $skip == 1 ]] && echo "Skip: $table_name ; size: ${size}MB" && continue
    echo "Checking: $table_name"
    check_table $table_name
    [[ $? -ne 0 ]] && STATUS=1
done < <(mysql -h$DB_HOST -u$DB_USER -p$DB_PASS -Bs $DB -e "$TABLES_SQL")

exit $STATUS
