# InfluxDB Tools

## Description

This repo is used to store some usefull script for influxdb management

## Scripts

* create_database.sh : create a database and a user in influxdb
Usage :
```
./create_database.sh <database_name> <user_password>
```

* retention_policy.sh : create retention policy in influxdb
Usage :
```
./retention_policy.sh <database_name>
```

This script will :
 * alter the **default** retention policy to keep data for 7 days.
 * Create a **rp_1h** retention policy with 365d of rentention
 * Create a **rp_1d** retention policy with 365d of rentention
 * For each measurement, it will also :
  * create a continuous query to aggreate all metrics to hour
  * mean + max are stored for fields like 'max'
  * mean + sum are stored for field like 'nb'
  * mean for other fields
