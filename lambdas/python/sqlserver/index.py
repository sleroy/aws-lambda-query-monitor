import os
import boto3
import json
import pymssql
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

#{
#  "sql": "SELECT COUNT(*) FROM demotable;",
#  "query_name": "Count number of records", 
#  "secret": "arn:aws:secretsmanager:us-east-1:787156592790:secret:prod/sqlserver/target-9GLIFX"
#}

region = os.environ.get('AWS_REGION')

def get_secret_value(secret_name):
    # Create a Secrets Manager client
    logger.info(f"Getting secret value for {secret_name}")
    secret_manager = boto3.client('secretsmanager', region_name=region)
    return secret_manager.get_secret_value(SecretId=secret_name)

def handler(context, event):
    logger.info("Starting handler execution")
    logger.info(f"Received event: {json.dumps({'context': context, 'event': event})}")

    # Get query and query name from the event
    query_sql = context['sql']  # Replace with the actual query
    query_name = context['query_name']
    secret_manager_id = context['db_secret']
    
    logger.info(f"Processing query: {query_name}")

    # Retrieve database credentials from AWS Secrets Manager
    logger.info("Retrieving database credentials")
    secret_response = get_secret_value(secret_manager_id)
    secret = json.loads(secret_response['SecretString'])

    db_username = secret['username']
    db_host = secret['host']
    db_name = secret['database']
    db_port = int(secret.get('port', 1433))
    
    logger.info(f"Connecting to database {db_name} on host {db_host}")

    # Connect to the SQL Server database
    status = 200
    connection_time = 0
    response_time = 0

    try:
        start_connection_time = datetime.now()

        conn = pymssql.connect(
            user=db_username,
            password=secret['password'],
            server=db_host,
            database=db_name,
            port=db_port
        )

        connection_time = (datetime.now() - start_connection_time).total_seconds()
        logger.info(f"Database connection established in {connection_time:.2f} seconds")

        cursor = conn.cursor()

        # Execute the SQL query and measure the response time
        logger.info(f"Executing query: {query_sql}")
        start_time = datetime.now()
        cursor.execute(query_sql)
        results = cursor.fetchall()
        end_time = datetime.now()
        response_time = (end_time - start_time).total_seconds()
        logger.info(f"Query executed successfully in {response_time:.2f} seconds")

        cursor.close()
        conn.close()
        logger.info("Database connection closed")

    except Exception as err:
        logger.error(f"Query execution failed: {err}")
        status = 500

    # Send the response time metric to Amazon CloudWatch
    logger.info("Sending metrics to CloudWatch")
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

    cloudwatch.put_metric_data(
        MetricData=[
            {
                'MetricName': 'SQLQueryResponseStatus',
                'Dimensions': [
                    {
                        'Name': 'QueryName',
                        'Value': query_name
                    }
                ],
                'Value': status
            }
        ],
        Namespace=db_name
    )

    cloudwatch.put_metric_data(
        MetricData=[
            {
                'MetricName': 'SQLQueryConnectionTime',
                'Dimensions': [
                    {
                        'Name': 'QueryName',
                        'Value': query_name
                    }
                ],
                'Value': connection_time
            }
        ],
        Namespace=db_name
    )
    
    logger.info("CloudWatch metrics sent successfully")

    response = {
        'statusCode': status,
        'body': {
            'message': f"SQL query {'executed' if status == 200 else 'failed'} in {response_time:.2f} seconds"
        }
    }
    logger.info(f"Handler completed with response: {json.dumps(response)}")
    return response

if __name__ == "__main__":
    # Example usage
    context = {
        "sql": "SELECT COUNT(*) FROM demotable;",
        "query_name": "Count number of records",
        "db_secret": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    }
    event = {}  # You can add any event data here if needed
    handler(context, event)
