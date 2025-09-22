// create-table.js - Script para crear la tabla DynamoDB
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { CreateTableCommand } = require('@aws-sdk/client-dynamodb');

const client = new DynamoDBClient({ region: 'us-east-1' });

async function createTable() {
    const command = new CreateTableCommand({
        TableName: 'device-locations',
        KeySchema: [
            { AttributeName: 'deviceId', KeyType: 'HASH' },
            { AttributeName: 'timestamp', KeyType: 'RANGE' }
        ],
        AttributeDefinitions: [
            { AttributeName: 'deviceId', AttributeType: 'S' },
            { AttributeName: 'timestamp', AttributeType: 'N' }
        ],
        BillingMode: 'PAY_PER_REQUEST',
        TimeToLiveSpecification: {
            AttributeName: 'ttl',
            Enabled: true
        },
        Tags: [
            { Key: 'Project', Value: 'GPS-Tracking' },
            { Key: 'Environment', Value: 'production' }
        ]
    });

    try {
        const result = await client.send(command);
        console.log('Tabla creada exitosamente:', result);
    } catch (error) {
        console.error('Error creando tabla:', error);
    }
}

createTable();