const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, QueryCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');

// Configuración del servidor
const app = express();
const PORT = process.env.PORT || 3000;
const REGION = process.env.AWS_REGION || 'us-east-1';
const TABLE_NAME = 'device-locations';

// Configuración de AWS DynamoDB
const dynamoClient = new DynamoDBClient({
    region: REGION,
    // Las credenciales se obtienen automáticamente del IAM role de EC2
});
const docClient = DynamoDBDocumentClient.from(dynamoClient);

// Middleware de seguridad y configuración
app.use(helmet()); // Seguridad básica
app.use(cors({
    origin: ['http://localhost:3000', 'https://tu-dominio-frontend.com'],
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
}));

// Rate limiting - máximo 100 requests por IP por minuto
const limiter = rateLimit({
    windowMs: 60 * 1000, // 1 minuto
    max: 100, // máximo 100 requests por ventana
    message: {
        error: 'Demasiadas solicitudes, intenta de nuevo en un minuto'
    },
    standardHeaders: true,
    legacyHeaders: false,
});
app.use('/api/', limiter);

// Parser para JSON con límite de tamaño
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Middleware para logging
app.use((req, res, next) => {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] ${req.method} ${req.path} - IP: ${req.ip}`);
    next();
});

// ===== RUTAS DE LA API =====

/**
 * Endpoint para recibir ubicaciones desde las aplicaciones móviles
 * POST /api/location
 */
app.post('/api/location', async (req, res) => {
    try {
        // Validar datos de entrada
        const { deviceId, timestamp, latitude, longitude, accuracy, deviceName } = req.body;
        
        if (!deviceId || !timestamp || latitude === undefined || longitude === undefined) {
            return res.status(400).json({
                error: 'Faltan campos requeridos: deviceId, timestamp, latitude, longitude'
            });
        }
        
        // Validar rangos de coordenadas
        if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
            return res.status(400).json({
                error: 'Coordenadas inválidas'
            });
        }
        
        // Validar timestamp (no puede ser futuro ni muy antiguo)
        const now = Date.now();
        if (timestamp > now + 60000 || timestamp < now - 86400000) { // 1 min futuro, 24h pasado
            return res.status(400).json({
                error: 'Timestamp inválido'
            });
        }
        
        // Preparar item para DynamoDB
        const locationItem = {
            deviceId: deviceId,
            timestamp: timestamp,
            latitude: parseFloat(latitude),
            longitude: parseFloat(longitude),
            accuracy: accuracy ? parseFloat(accuracy) : null,
            deviceName: deviceName || 'Unknown Device',
            receivedAt: now, // Timestamp del servidor
            ttl: Math.floor((now + 30 * 24 * 60 * 60 * 1000) / 1000) // TTL 30 días
        };
        
        // Guardar en DynamoDB
        const command = new PutCommand({
            TableName: TABLE_NAME,
            Item: locationItem
        });
        
        await docClient.send(command);
        
        // Log exitoso
        console.log(`Ubicación guardada para dispositivo ${deviceId}: ${latitude}, ${longitude}`);
        
        // Respuesta exitosa
        res.status(201).json({
            success: true,
            message: 'Ubicación guardada exitosamente',
            deviceId: deviceId,
            timestamp: timestamp
        });
        
    } catch (error) {
        console.error('Error guardando ubicación:', error);
        res.status(500).json({
            error: 'Error interno del servidor',
            message: 'No se pudo guardar la ubicación'
        });
    }
});

/**
 * Endpoint para obtener ubicaciones de un dispositivo específico
 * GET /api/locations?deviceId=xxx&startTime=xxx&endTime=xxx&limit=xxx
 */
app.get('/api/locations', async (req, res) => {
    try {
        const { deviceId, startTime, endTime, limit } = req.query;
        
        if (!deviceId) {
            return res.status(400).json({
                error: 'deviceId es requerido'
            });
        }
        
        // Configurar parámetros de consulta
        const queryParams = {
            TableName: TABLE_NAME,
            KeyConditionExpression: 'deviceId = :deviceId',
            ExpressionAttributeValues: {
                ':deviceId': deviceId
            },
            ScanIndexForward: false, // Orden descendente por timestamp
            Limit: limit ? parseInt(limit) : 100
        };
        
        // Agregar filtro de tiempo si se proporciona
        if (startTime || endTime) {
            let timeCondition = '';
            if (startTime && endTime) {
                timeCondition = '#ts BETWEEN :startTime AND :endTime';
                queryParams.ExpressionAttributeValues[':startTime'] = parseInt(startTime);
                queryParams.ExpressionAttributeValues[':endTime'] = parseInt(endTime);
            } else if (startTime) {
                timeCondition = '#ts >= :startTime';
                queryParams.ExpressionAttributeValues[':startTime'] = parseInt(startTime);
            } else if (endTime) {
                timeCondition = '#ts <= :endTime';
                queryParams.ExpressionAttributeValues[':endTime'] = parseInt(endTime);
            }
            
            queryParams.FilterExpression = timeCondition;
            queryParams.ExpressionAttributeNames = { '#ts': 'timestamp' };
        }
        
        // Ejecutar consulta
        const command = new QueryCommand(queryParams);
        const result = await docClient.send(command);
        
        // Formatear respuesta
        const locations = result.Items.map(item => ({
            deviceId: item.deviceId,
            timestamp: item.timestamp,
            latitude: item.latitude,
            longitude: item.longitude,
            accuracy: item.accuracy,
            deviceName: item.deviceName
        }));
        
        res.json({
            success: true,
            count: locations.length,
            deviceId: deviceId,
            locations: locations
        });
        
    } catch (error) {
        console.error('Error obteniendo ubicaciones:', error);
        res.status(500).json({
            error: 'Error interno del servidor',
            message: 'No se pudieron obtener las ubicaciones'
        });
    }
});

/**
 * Endpoint para obtener lista de dispositivos activos
 * GET /api/devices?hours=24 (últimas 24 horas por defecto)
 */
app.get('/api/devices', async (req, res) => {
    try {
        const hours = parseInt(req.query.hours) || 24;
        const timeThreshold = Date.now() - (hours * 60 * 60 * 1000);
        
        // Usar scan con filtro para encontrar dispositivos activos
        // En producción, esto debería ser optimizado con un GSI
        const scanParams = {
            TableName: TABLE_NAME,
            FilterExpression: '#ts >= :timeThreshold',
            ExpressionAttributeNames: {
                '#ts': 'timestamp'
            },
            ExpressionAttributeValues: {
                ':timeThreshold': timeThreshold
            }
        };
        
        const command = new ScanCommand(scanParams);
        const result = await docClient.send(command);
        
        // Agrupar por deviceId y obtener la ubicación más reciente
        const deviceMap = new Map();
        
        result.Items.forEach(item => {
            const deviceId = item.deviceId;
            if (!deviceMap.has(deviceId) || item.timestamp > deviceMap.get(deviceId).timestamp) {
                deviceMap.set(deviceId, {
                    deviceId: item.deviceId,
                    deviceName: item.deviceName,
                    lastLocation: {
                        timestamp: item.timestamp,
                        latitude: item.latitude,
                        longitude: item.longitude,
                        accuracy: item.accuracy
                    }
                });
            }
        });
        
        const devices = Array.from(deviceMap.values());
        
        res.json({
            success: true,
            count: devices.length,
            timeRange: `${hours} horas`,
            devices: devices
        });
        
    } catch (error) {
        console.error('Error obteniendo dispositivos:', error);
        res.status(500).json({
            error: 'Error interno del servidor',
            message: 'No se pudieron obtener los dispositivos'
        });
    }
});

/**
 * Endpoint para obtener estadísticas del sistema
 * GET /api/stats
 */
app.get('/api/stats', async (req, res) => {
    try {
        const last24h = Date.now() - (24 * 60 * 60 * 1000);
        const last1h = Date.now() - (60 * 60 * 1000);
        
        // Contar ubicaciones en las últimas 24 horas
        const scan24h = new ScanCommand({
            TableName: TABLE_NAME,
            FilterExpression: '#ts >= :time24h',
            ExpressionAttributeNames: { '#ts': 'timestamp' },
            ExpressionAttributeValues: { ':time24h': last24h },
            Select: 'COUNT'
        });
        
        // Contar ubicaciones en la última hora
        const scan1h = new ScanCommand({
            TableName: TABLE_NAME,
            FilterExpression: '#ts >= :time1h',
            ExpressionAttributeNames: { '#ts': 'timestamp' },
            ExpressionAttributeValues: { ':time1h': last1h },
            Select: 'COUNT'
        });
        
        const [result24h, result1h] = await Promise.all([
            docClient.send(scan24h),
            docClient.send(scan1h)
        ]);
        
        res.json({
            success: true,
            statistics: {
                locationsLast24h: result24h.Count,
                locationsLastHour: result1h.Count,
                serverTime: new Date().toISOString(),
                uptime: process.uptime()
            }
        });
        
    } catch (error) {
        console.error('Error obteniendo estadísticas:', error);
        res.status(500).json({
            error: 'Error interno del servidor'
        });
    }
});

// ===== RUTAS DE SALUD Y MONITOREO =====

/**
 * Health check endpoint
 * GET /health
 */
app.get('/health', (req, res) => {
    res.json({
        status: 'OK',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        memory: process.memoryUsage(),
        version: process.env.npm_package_version || '1.0.0'
    });
});

/**
 * Endpoint de información del servidor
 * GET /info
 */
app.get('/info', (req, res) => {
    res.json({
        name: 'GPS Tracking Server',
        version: '1.0.0',
        description: 'Servidor backend para tracking GPS de dispositivos móviles',
        endpoints: {
            'POST /api/location': 'Recibir ubicación de dispositivo',
            'GET /api/locations': 'Obtener ubicaciones de un dispositivo',
            'GET /api/devices': 'Listar dispositivos activos',
            'GET /api/stats': 'Estadísticas del sistema',
            'GET /health': 'Estado del servidor'
        }
    });
});

// ===== MANEJO DE ERRORES Y MIDDLEWARE FINAL =====

/**
 * Middleware para rutas no encontradas
 */
app.use('*', (req, res) => {
    res.status(404).json({
        error: 'Endpoint no encontrado',
        message: `La ruta ${req.method} ${req.originalUrl} no existe`,
        availableEndpoints: ['/api/location', '/api/locations', '/api/devices', '/health', '/info']
    });
});

/**
 * Middleware global de manejo de errores
 */
app.use((error, req, res, next) => {
    console.error('Error no manejado:', error);
    res.status(500).json({
        error: 'Error interno del servidor',
        message: 'Algo salió mal procesando tu solicitud'
    });
});

// ===== INICIALIZACIÓN DEL SERVIDOR =====

/**
 * Función para verificar conexión con DynamoDB
 */
async function testDatabaseConnection() {
    try {
        const command = new ScanCommand({
            TableName: TABLE_NAME,
            Limit: 1
        });
        await docClient.send(command);
        console.log('✓ Conexión con DynamoDB establecida correctamente');
        return true;
    } catch (error) {
        console.error('✗ Error conectando con DynamoDB:', error.message);
        return false;
    }
}

/**
 * Iniciar el servidor
 */
async function startServer() {
    try {
        // Verificar conexión con la base de datos
        const dbConnected = await testDatabaseConnection();
        
        if (!dbConnected) {
            console.error('No se puede iniciar el servidor sin conexión a la base de datos');
            process.exit(1);
        }
        
        // Iniciar servidor HTTP
        const server = app.listen(PORT, '0.0.0.0', () => {
            console.log(`
╔════════════════════════════════════════════════════════════════╗
║                    GPS TRACKING SERVER                         ║
╠════════════════════════════════════════════════════════════════╣
║  Puerto: ${PORT.toString().padEnd(53)} ║
║  Región AWS: ${REGION.padEnd(49)} ║
║  Tabla DynamoDB: ${TABLE_NAME.padEnd(43)} ║
║  Estado: ACTIVO                                                ║
╚════════════════════════════════════════════════════════════════╝
            `);
            
            console.log('Endpoints disponibles:');
            console.log('  POST /api/location     - Recibir ubicaciones');
            console.log('  GET  /api/locations    - Consultar ubicaciones');
            console.log('  GET  /api/devices      - Listar dispositivos');
            console.log('  GET  /api/stats        - Estadísticas');
            console.log('  GET  /health           - Estado del servidor');
            console.log('');
        });
        
        // Manejo de cierre graceful
        process.on('SIGTERM', () => {
            console.log('Recibida señal SIGTERM, cerrando servidor...');
            server.close(() => {
                console.log('Servidor cerrado correctamente');
                process.exit(0);
            });
        });
        
        process.on('SIGINT', () => {
            console.log('Recibida señal SIGINT, cerrando servidor...');
            server.close(() => {
                console.log('Servidor cerrado correctamente');
                process.exit(0);
            });
        });
        
    } catch (error) {
        console.error('Error iniciando el servidor:', error);
        process.exit(1);
    }
}

// Iniciar el servidor
startServer();