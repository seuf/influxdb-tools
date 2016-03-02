#!/bin/sh

database=$1
password=$2
host=`hostname`

if [ -z ${database} ]; then
  echo "Usage : $0 database_name password"
  exit;
fi

if [ -z ${password} ]; then
  echo "Usage : $0 database_name password"
  exit;
fi

influx -database ${database} -host ${host} -execute "CREATE DATABASE ${database}"
influx -database ${database} -host ${host} -execute "CREATE USER ${database} WITH PASSWORD '${password}'"
influx -database ${database} -host ${host} -execute "GRANT ALL ON ${database} TO ${database}"
