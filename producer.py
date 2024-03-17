
import requests
import config
import json
from pprint import pprint
import confluent_kafka
import os


def get_countries_flags():
    """
        Retreive countries data and restruct it
        :input: None
        :ouput: List of json data that contain countries flags and their description
    """
    res = requests.get(config.URL)

    result =  [{
            "country_name": country["name"]["official"],
            "flag_description": country["flags"]["alt"],
            "flag_url": country["flags"]["png"]
            } for country in  res.json()]
    
    return result





def delivery_callback(err, msg):
    """
    Callback method
    """
    if err:
        print("Error",  str(err) +str(msg))
    else:
        print("Success",msg)


def kafka_producer(payload):
    """
    Publish Data
    """
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
    
    producer = confluent_kafka.Producer(**conf)

    producer.produce(f"{kafka_topic}", json.dumps(payload, default=str), callback=delivery_callback)
    
    producer.flush()



def lambda_handler(event, context):

    for payload in get_countries_flags():
        kafka_producer(payload)
    
    return {
        'statusCode': 200,
        'body': json.dumps('DSTI PROJ!')
    }




"""
if __name__ == "__main__":

    for country in get_countries_flags():
        pprint(country)"""