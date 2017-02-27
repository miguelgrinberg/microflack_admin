#!/bin/bash -e

# This script generates random database passwords for all database backed services.

PW_FILE=~/.mysql_passwords
if [[ ! -f $PW_FILE ]]; then
    touch $PW_FILE
fi

source $PW_FILE
for SERVICE in $SERVICES_WITH_DB; do
    VAR=$(echo ${SERVICE}_DB_PASSWORD | tr '/a-z/' '/A-Z/')
    if [[ "$(eval echo \$$VAR)" == "" ]]; then
        PASSWORD=$(pwgen -1 -c -n -s 16)
        echo "${VAR}=$PASSWORD" >> $PW_FILE
    fi
done
