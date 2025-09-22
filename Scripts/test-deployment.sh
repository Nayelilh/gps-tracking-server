# ===== test-deployment.sh - Script para probar el despliegue =====
#!/bin/bash

echo "Probando despliegue del sistema GPS Tracking..."

SERVER_URL=${1:-"http://localhost:3000"}
FRONTEND_URL=${2:-"http://localhost:8080"}

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Función para pruebas
test_endpoint() {
    local url=$1
    local description=$2
    local expected_status=${3:-200}
    
    echo -n "Probando $description... "
    
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    
    if [ "$status" -eq "$expected_status" ]; then
        echo -e "${GREEN}✓ OK${NC} ($status)"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} ($status)"
        return 1
    fi
}

# Función para probar POST
test_post() {
    local url=$1
    local data=$2
    local description=$3
    
    echo -n "Probando $description... "
    
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$data" \
        -w "%{http_code}" \
        "$url")
    
    status="${response: -3}"
    
    if [ "$status" -eq "201" ] || [ "$status" -eq "200" ]; then
        echo -e "${GREEN}✓ OK${NC} ($status)"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} ($status)"
        echo "Response: ${response%???}"
        return 1
    fi
}

echo "🧪 Iniciando pruebas del sistema..."
echo "Servidor: $SERVER_URL"
echo "Frontend: $FRONTEND_URL"
echo ""

# Pruebas del servidor
echo "📡 Probando servidor backend..."
test_endpoint "$SERVER_URL/health" "Health Check"
test_endpoint "$SERVER_URL/info" "Información del servidor"
test_endpoint "$SERVER_URL/api/devices" "Lista de dispositivos"

# Probar envío de ubicación
echo ""
echo "📍 Probando envío de ubicación..."
location_data='{
    "deviceId": "test-device-001",
    "timestamp": '$(date +%s000)',
    "latitude": -13.5319,
    "longitude": -71.9675,
    "accuracy": 10.5,
    "deviceName": "Dispositivo de Prueba"
}'

test_post "$SERVER_URL/api/location" "$location_data" "Envío de ubicación"

# Probar consulta de ubicaciones
echo ""
echo "📋 Probando consulta de datos..."
test_endpoint "$SERVER_URL/api/locations?deviceId=test-device-001&limit=10" "Consulta de ubicaciones"
test_endpoint "$SERVER_URL/api/stats" "Estadísticas del sistema"

# Pruebas del frontend
echo ""
echo "🌐 Probando frontend web..."
test_endpoint "$FRONTEND_URL" "Página principal"

# Pruebas de rendimiento básicas
echo ""
echo "⚡ Probando rendimiento..."
echo -n "Tiempo de respuesta del health check... "
response_time=$(curl -s -o /dev/null -w "%{time_total}" "$SERVER_URL/health")
echo "${response_time}s"

if (( $(echo "$response_time < 1.0" | bc -l) )); then
    echo -e "${GREEN}✓ Rendimiento OK${NC}"
else
    echo -e "${YELLOW}⚠ Respuesta lenta${NC}"
fi

echo ""
echo "🎯 Resumen de pruebas completado"
echo "Para monitoreo continuo, ejecuta este script regularmente"

# ===== monitor.sh - Script de monitoreo =====
#!/bin/bash

echo "🔍 Monitor del Sistema GPS Tracking"
echo "================================="

SERVER_URL=${1:-"http://localhost:3000"}

while true; do
    clear
    echo "🔍 Monitor GPS Tracking - $(date)"
    echo "Servidor: $SERVER_URL"
    echo "================================="
    
    # Estado del servidor
    if curl -s "$SERVER_URL/health" > /dev/null; then
        echo -e "🟢 Servidor: ACTIVO"
    else
        echo -e "🔴 Servidor: INACTIVO"
    fi
    
    # Estadísticas
    stats=$(curl -s "$SERVER_URL/api/stats" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "📊 Estadísticas:"
        echo "$stats" | jq -r '
            "  • Ubicaciones 24h: \(.statistics.locationsLast24h // "N/A")",
            "  • Ubicaciones 1h: \(.statistics.locationsLastHour // "N/A")",
            "  • Uptime: \(.statistics.uptime // "N/A")s"
        ' 2>/dev/null || echo "  Error obteniendo estadísticas"
    fi
    
    # Dispositivos activos
    devices=$(curl -s "$SERVER_URL/api/devices" 2>/dev/null)
    if [ $? -eq 0 ]; then
        device_count=$(echo "$devices" | jq -r '.count // 0' 2>/dev/null)
        echo "📱 Dispositivos activos: ${device_count:-"N/A"}"
    fi
    
    echo ""
    echo "Presiona Ctrl+C para salir"
    sleep 30
done

echo ""
echo "Configuración de archivos completada."
echo "Archivos generados:"
echo "  • deploy.sh - Script principal de despliegue"  
echo "  • setup-ec2.sh - Configuración del servidor EC2"
echo "  • create-android-config.sh - Configuración Android"
echo "  • test-deployment.sh - Pruebas del sistema"
echo "  • monitor.sh - Monitoreo en tiempo real" "