-- Note while executing this query using docker u need to consider back ticks so either use single quotes to run this query using clickhouse client on docker-- 
-- Let’s take 1b rows from the Wikistat dataset as an example: -- 
CREATE TABLE wikistat
(
    `time` DateTime CODEC(Delta(4), ZSTD(1)),
    `project` LowCardinality(String),
    `subproject` LowCardinality(String),
    `path` String,
    `hits` UInt64
)
ENGINE = MergeTree
ORDER BY (path, time);

INSERT INTO wikistat SELECT * FROM s3('https://ClickHouse-public-datasets.s3.amazonaws.com/wikistat/partitioned/wikistat*.native.zst', 'Native') LIMIT 1e9

-- Suppose we frequently query for the most popular projects for a certain date: --

SELECT
    project,
    sum(hits) AS h
FROM wikistat
WHERE date(time) = '2015-05-01'
GROUP BY project
ORDER BY h DESC
LIMIT 10

-- This query takes a ClickHouse Cloud development service 15 seconds to complete IN mac around 2.16 second obv i didnt store all rows: --
-- there are these many rows right now in db while testing this 438301959 --

-- If we have plenty of those queries and we need subsecond performance from ClickHouse, we can create a materialized view for this query: -- 

CREATE TABLE wikistat_top_projects
(
    `date` Date,
    `project` LowCardinality(String),
    `hits` UInt32
)
ENGINE = SummingMergeTree
ORDER BY (date, project);

CREATE MATERIALIZED VIEW wikistat_top_projects_mv TO wikistat_top_projects AS
SELECT
    date(time) AS date,
    project,
    sum(hits) AS hits
FROM wikistat
GROUP BY
    date,
    project;

/* In these two queries:
wikistat_top_projects is the name of the table that we’re going to use to save a materialized view,
wikistat_top_projects_mv is the name of the materialized view itself (the trigger),
we’ve used SummingMergeTree because we would like to have our hits value summarized for each date/project pair,
everything that comes after AS is the query that the materialized view will be built from.
We can create any number of materialized views, but each new materialized view is an additional storage load, so keep the overall number sensible i.e. aim for under 10 per table.
Now let’s populate the materialized view’s target table with the data from wikistat table using the same query: 
*/

INSERT INTO wikistat_top_projects SELECT
    date(time) AS date,
    project,
    sum(hits) AS hits
FROM wikistat
GROUP BY
    date,
    project


-- Since wikistat_top_projects is a table, we have all of the power of ClickHouse SQL to query it: -- 

SELECT
    project,
    sum(hits) AS hits
FROM wikistat_top_projects
WHERE date = '2015-05-01'
GROUP BY project
ORDER BY hits DESC
LIMIT 10;

-- this query only takes 0.003 sec to give result as compared to 2.x seconds above to give same output

/* 
All metadata on materialized view tables is available in the system database like any other table. E.g., to get its size on disk, we can do the following:
*/

SELECT
    total_rows,
    formatReadableSize(total_bytes) AS total_bytes_on_disk
FROM system.tables
WHERE name = 'wikistat_top_projects'

/* 
-> The most powerful feature of materialized views is that the data is updated automatically in the target table, when it is inserted into the source tables using the SELECT statement:
-> So we don’t have to additionally refresh data in the materialized view - everything is done automatically by ClickHouse. Suppose we insert new data into the wikistat table:
*/

INSERT INTO wikistat
VALUES(now(), 'test', '', '', 10),
      (now(), 'test', '', '', 10),
      (now(), 'test', '', '', 20),
      (now(), 'test', '', '', 30);

/* 
Now let’s query the materialized view’s target table to verify the hits column is summed properly. We use FINAL modifier to make sure the summing engine returns summarized hits instead of individual, unmerged rows:
*/

SELECT hits
FROM wikistat_top_projects
FINAL
WHERE (project = 'test') AND (date = date(now()))

/* 
As shown in the previous section, materialized views are a way to improve query performance. All kinds of aggregations are common for analytical queries, not only sum() as shown in the previous example. The SummingMergeTree is useful for keeping a total of values, but there are more advanced aggregations that can be computed using the AggregatingMergeTree engine.
Suppose we have the following type of query being executed frequently:
*/

SELECT
    toDate(time) AS date,
    min(hits) AS min_hits_per_hour,
    max(hits) AS max_hits_per_hour,
    avg(hits) AS avg_hits_per_hour
FROM wikistat
WHERE project = 'en'
GROUP BY date

-- Note here that our raw data is already aggregated by the hour.-- 

/* 
Let's store these aggregated results using a materialized view for faster retrieval. Aggregated results are defined using state combinators. State combinators ask ClickHouse to save the internal aggregated state instead of the final aggregation result. This allows using aggregations without having to save all records with original values. The approach is quite simple - we use *State() functions when creating materialized views and then their corresponding *Merge() functions at query time to get the correct aggregate results:
*/