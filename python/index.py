
import os
import sys
import json
import logging
import time
import json
from pprint import pformat

# Hack to use dependencies from lib directory
BASE_PATH = os.path.dirname(__file__)
sys.path.append(BASE_PATH + "/lib")


LOGGER = logging.getLogger(__name__)
logging.getLogger().setLevel(logging.INFO)

import boto3
import pyodbc
import boto3
from botocore.exceptions import ClientError


def get_secret(secret_manager_id: str):

    secret_name = secret_manager_id
    region_name = "us-east-1"

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        raise e

    secret = get_secret_value_response['SecretString']
    return json.loads(secret)


def lambda_handler(event, context):
    LOGGER.info("%s", pformat({"Context" : vars(context), "Request": event}))
    
    # Get query and query name from the event
    query_sql = event['sql']  # Replace with the actual query_
    query_name = event['query_name']
    secret_manager_id = event['db_secret']    


    # Retrieve database credentials from AWS Secrets Manager
    secret_response = get_secret(secret_manager_id)
    db_username = secret_response['username']
    db_password = secret_response['password']
    db_host = secret_response['host']
    db_name = secret_response['database']
    db_port = secret_response['port']
    
    # Connect to the SQL Server database
    connection_string = f'DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={db_host},{db_port};DATABASE={db_name};UID={db_username};PWD={db_password}'
    conn = pyodbc.connect(connection_string)
    cursor = conn.cursor()

    # Execute the SQL query and measure the response time
    start_time = time.time()
    cursor.execute(query_sql)
    results = cursor.fetchall()
    end_time = time.time()
    response_time = end_time - start_time

    # Send the response time metric to Amazon CloudWatch
    cloudwatch = boto3.client('cloudwatch')
    cloudwatch.put_metric_data(
        MetricData=[
            {
                'MetricName': 'SQLQueryResponseTime',
                'Dimensions': [
                    {
                        'Name': 'QueryName',
                        'Value': query_name
                    }
                ],
                'Value': response_time
            }
        ],
        Namespace=db_name
    )

    return {
        'statusCode': 200,
        'body': f'SQL query executed in {response_time:.2f} seconds'
    }


if __name__ == '__main__':
    # Do nothing if executed as a script
    pass        