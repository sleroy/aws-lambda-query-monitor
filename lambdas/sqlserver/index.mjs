import AWS from 'aws-sdk';
const SecretsManager = new AWS.SecretsManager();
import mssql from 'mssql'
import {exec} from 'node:child_process';

const region = process.env.AWS_REGION;

async function getSecretValue(secretName) {

    // Create a Secrets Manager client
    var secretManager = new AWS.SecretsManager({
        region: region
    });
    return await secretManager.getSecretValue({ SecretId: secretName }).promise();
}

export const handler = async (context, event) => {

    console.log(JSON.stringify({ context: context, event: event }));

    // Get query and query name from the event
    const query_sql = context.sql;  // Replace with the actual query_
    const query_name = context.query_name;
    const secret_manager_id = context.db_secret;
  
    // Retrieve database credentials from AWS Secrets Manager
    const secret_response = await getSecretValue(secret_manager_id);
    const secret = JSON.parse(secret_response.SecretString);
  
    const db_username = secret.username;
    const db_password = secret.password;
    const db_host = secret.host;
    const db_name = secret.database;
    const db_port = Number.parseInt(secret.port | "1433");

    // Connect to the SQL Server database
    const pool = new mssql.ConnectionPool({
        user: db_username,
        password: db_password,
        server: db_host,
        database: db_name,
        port: db_port,
        dialect: "mssql",
        options: {
            encrypt: false,
            trustServerCertificate: true,
            trustedConnection: true,  
        },
    });

    let status = 200;
    let connection_time = 0;
    let response_time = 0;
    try {
        const start_connection_time = Date.now()

        const conn = await pool.connect();
        connection_time = (Date.now() - start_connection_time) / 1000;

        const request = new pymssql.Request(conn);

        // Execute the SQL query and measure the response time
        const start_time = Date.now();
        const results = await request.query(query_sql);
        const end_time = Date.now();
        response_time = (end_time - start_time) / 1000;

        conn.close();
    } catch (err) {
        console.error("Execution has failed", err);
        status = 500;
    }
    // Send the response time metric to Amazon CloudWatch
    const cloudwatch = new AWS.CloudWatch();

    await cloudwatch.putMetricData({
        MetricData: [
            {
                MetricName: 'SQLQueryResponseTime',
                Dimensions: [
                    {
                        Name: 'QueryName',
                        Value: query_name
                    }
                ],
                Value: response_time
            }
        ],
        Namespace: db_name
    }).promise();

    await cloudwatch.putMetricData({
        MetricData: [
            {
                MetricName: 'SQLQueryResponseStatus',
                Dimensions: [
                    {
                        Name: 'QueryName',
                        Value: query_name
                    }
                ],
                Value: status
            }
        ],
        Namespace: db_name
    }).promise();
    await cloudwatch.putMetricData({
        MetricData: [
            {
                MetricName: 'SQLQueryConnectionTime',
                Dimensions: [
                    {
                        Name: 'QueryName',
                        Value: query_name
                    }
                ],
                Value: connection_time
            }
        ],
        Namespace: db_name
    }).promise();

    return {
        statusCode: status,
        body: {
            message: `SQL query ${(status == 200) ? "executed " : "failed "} in ${response_time.toFixed(2)} seconds`,
        }
    };
};