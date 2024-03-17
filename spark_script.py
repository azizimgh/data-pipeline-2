import findspark
import sys 
from pyspark.sql import SparkSession
import config

findspark.init()


def consume_queue():
    nums = [1, 2, 3, 4]
    return nums.map(lambda x: x * x).collect()


if __name__ == "__main__":
    """
      Sends the output into an s3 bucket
    """

    spark = SparkSession.builder.appName("Demo").getOrCreate()

    output_path = config.DSTI_BUCKET

    output = consume_queue()

    spark.sparkContext.parallelize(output).saveAsTextFile(
        output_path
    )