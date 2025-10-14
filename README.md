** Clickhouse **

 * data doesn’t only have to be stored, but processed as well. 
 * Processing is usually done on an application side using one of the available libraries for ClickHouse.
 * Still, there are some critical processing points that can be moved to ClickHouse to increase the performance and manageability of the data. One of the most powerful tools for that in ClickHouse is Materialized Views.

-> Materialized View 
 * A materialized view is a special trigger that stores the result of a SELECT query on data, as it is inserted, into a target table
 * can be used in ClickHouse for accelerating queries as well as data transformation, filtering and routing tasks.

 docker run -d -p 8123:8123 -p 9000:9000 -e CLICKHOUSE_PASSWORD=CHANGEME --name clickhouse-server --ulimit nofile=262144:262144 clickhouse

 echo 'SELECT version()' | curl 'http://localhost:8123/?password=CHANGEME' --data-binary @-

 docker exec -it clickhouse-server clickhouse-client --query "SHOW DATABASES;"

 docker exec -it clickhouse-server clickhouse-client --query "SHOW TABLES FROM default;"