import socket
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder
    .appName("USTH-Spark-Smoke-Test")
    .getOrCreate()
)

sc = spark.sparkContext

def identify_executor(iterator):
    host = socket.gethostname()
    count = sum(1 for _ in iterator)
    yield (host, count)

rdd = sc.parallelize(range(100000), 32)

result = rdd.mapPartitions(
    identify_executor
).collect()

print("Executor hosts and partitions:")
for host, count in result:
    print(host, count)

print("Total records:", sum(count for _, count in result))

# Test HDFS write
df = spark.range(0, 100000)

df.write.mode("overwrite").parquet(
    "hdfs:///spark-test/output"
)

# Test HDFS read
read_df = spark.read.parquet(
    "hdfs:///spark-test/output"
)

print("HDFS record count:", read_df.count())

spark.stop()