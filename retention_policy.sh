#!/bin/bash

database=$1
measurement=$2
host=`hostname`

if [ -z ${database} ]; then
  echo "Usage : $0 [database name]"
  exit;
fi

date_now=$(date "+%Y-%m-%d %H:%M:%S")
date_last_week=$(date "+%Y-%m-%d %H:%M:%S" -d "1 week ago")

### Retention Policies
echo "Updating default RP to keep data 7d on database $host:$database"
influx -database ${database} -host ${host} -execute "ALTER RETENTION POLICY default ON ${database} DURATION 7d REPLICATION 3 DEFAULT"
echo "Creating rp_1h RP to keep data 365d with 1h mean on database $host:$database"
influx -database ${database} -host ${host} -execute "CREATE RETENTION POLICY rp_1h ON ${database} DURATION 365d REPLICATION 3"

continuous_queries=$(influx -database ${database} -host ${host} -execute "SHOW CONTINUOUS QUERIES" | grep -v "name:" | grep -v "\-\-\-\-" | grep -E -v "name\s+query" |grep -v "^$" | grep ${database} | awk '{ print $1 }')
echo "Existing continuous queries :"
for c in ${continuous_queries}
do
  echo ${c}
done
echo ""

### Continuous Queries
measurements=$(influx -database ${database} -host ${host} -execute "SHOW MEASUREMENTS" 2>&1 | grep -v "name" | grep -v "measurement" | grep -v "\-\-\-\-\-\-" )

for m in ${measurements}
do
  exec_query=true
  if [ "${measurement}" != "" ]; then
    if [ "${measurement}" != "${m}" ]; then
      exec_query=false
    fi
  fi
  if [ ${exec_query} == false ]; then
    continue
  fi


  fields=$(influx -database ${database} -host ${host} -execute "SHOW FIELD KEYS FROM ${m}" | grep -v fieldKey | grep -v ${m} | grep -v "\-\-\-\-\-\-" )
  tags=$(influx -database ${database} -host ${host} -execute "SHOW TAG KEYS FROM ${m}" | grep -v name | grep -v ${m} | grep -v "\-\-\-\-\-\-" )

  echo "Creating continuous Query for measurement : ${m}"
  influx -database ${database} -host ${host} -execute "DROP CONTINUOUS QUERY cq_1h_${m} ON ${database}"
  query="CREATE CONTINUOUS QUERY cq_1h_${m} ON ${database} BEGIN SELECT "
  avg=false
  sum_field=""
## Listing all field to find a sum field (ie nbHits / msgReceived) to calculate weighted avg
  for f in ${fields}
  do
    echo ${f} | grep -E -i "nb|received" > /dev/null
    if [ $? -eq 0 ]; then
      sum_field=${f}
    fi
    echo ${f} | grep -E -i "weighting" > /dev/null
    if [ $? -eq 0 ]; then
      avg=true
    fi
  done

## Generating query
  for f in ${fields}
  do
    # NB fields are summed
    echo ${f} | grep -E -i "nb" > /dev/null
    if [ $? -eq 0 ]; then
      query="${query} sum(${f}) as ${f},"
    else
      # MAX fields are maxed and meaned
      echo ${f} | grep -E -i "max" > /dev/null
      if [ $? -eq 0 ]; then
        query="${query} max(${f}) as ${f}, mean(${f}) as avg_${f},"
      else
        # OTHER FIELDS are meaned
        query="${query} mean(${f}) as ${f},"
      fi
    fi
  done
  query="${query} count(${f}) as metrics_count,"
  query=${query%,}
  query="${query} INTO ${database}.\"rp_1h\".${m}"
  query="${query} FROM ${m} GROUP BY time(1h)"
  for t in ${tags}
  do
    query="${query},${t}"
  done
  query="${query} END"

  echo "  Query :"
  echo "  ${query}"
  echo ""
  influx -database ${database} -host ${host} -execute "${query}"


## BACK FILLING
  echo "Back filling data for measurement : ${m}"
  backfill_query="SELECT "

  for f in ${fields}
  do
    # NB fields are summed
    echo ${f} | grep -E -i "nb" > /dev/null
    if [ $? -eq 0 ]; then
      backfill_query="${backfill_query} sum(${f}) as ${f},"
    else
      # MAX fields are maxed and meaned
      echo ${f} | grep -E -i "max" > /dev/null
      if [ $? -eq 0 ]; then
        backfill_query="${backfill_query} max(${f}) as ${f}, mean(${f}) as avg_${f},"
      else
        # OTHER fields are meaned
        backfill_query="${backfill_query} mean(${f}) as ${f},"
      fi
    fi
  done
  backfill_query="${backfill_query} count(${f}) as metrics_count,"
  backfill_query=${backfill_query%,}
  backfill_query="${backfill_query} INTO ${database}.\"rp_1h\".${m} FROM ${m} WHERE time > '$date_last_week' AND time < '$date_now' GROUP BY time(1h)"
  for t in ${tags}
  do
    backfill_query="${backfill_query},${t}"
  done
  echo ${backfill_query}
  echo ""
  influx -database ${database} -host ${host} -execute "${backfill_query}"
done

