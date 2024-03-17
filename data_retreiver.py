
import requests
import config
import json
from pprint import pprint


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





if __name__ == "__main__":
    """
       If the script is launched we can use it as a test
    """

    for country in get_countries_flags():
        pprint(country)