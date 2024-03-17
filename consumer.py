import json
import config
import confluent_kafka
import os
import boto3
import requests
from PIL import Image
import io


def get_png_image(url):

    response = requests.get(url)
    image_data = response.content
    
    try:
        image = Image.open(io.BytesIO(image_data))
        return image
    except Exception as e:
        print("Error", e)
        return None


def kafka_consumer():
    kafka_topic = config.TOPIC
    
    conf = {
        "bootstrap.servers": config.BROKERS,
        "socket.timeout.ms": 10000,
        "security.protocol": "SASL_SSL",
        "sasl.mechanisms": "SCRAM-SHA-512",
        "sasl.username": config.USERNAME,
        "sasl.password": config.PASSWORD,
        "broker.version.fallback": "0.9.0",
        "api.version.request": True,
        "auto.offset.reset": "latest",
        "batch.num.messages": 100,
    }
    

    consumer = confluent_kafka.Consumer(**conf)

    consumer.subscribe([kafka_topic])

    return consumer

def write_to_s3(bucket_name, name, data):
    s3 = boto3.client('s3')
    s3.put_object(Bucket=bucket_name, Key=name, Body=data)

def lambda_handler(event, context):
    kafka_consumer_instance = kafka_consumer()
    bucket_name = os.environ["s3_bucket_name"]


    while True:
        message = kafka_consumer_instance.poll(timeout=1.0)
        if message is None:
            continue
        if message.error():
            raise confluent_kafka.KafkaException(message.error())
        else:

            json_format = json.loads(message.value())
            content =  get_png_image(json_format["flag_url"])
            write_to_s3(bucket_name, json_format["country_name"], content)
            print("Message written to S3:", message.value())

    return {
        'statusCode': 200,
        'body': json.dumps('Messages written to S3!')
    }
