# ===== deploy.sh - Script principal de despliegue =====
#!/bin/bash

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    GPS TRACKING DEPLOYMENT                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"

# Configuración
REGION="us-east-1"
INSTANCE_TYPE="t3.micro"
KEY_NAME="gps-tracking-key"
SECURITY_GROUP="gps-tracking-sg"
TABLE_NAME="device-locations"
BUCKET_NAME="gps-tracking-frontend-$(date +%s)"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI no está instalado"
    exit 1
fi

# Verificar credenciales AWS
if ! aws sts get-caller-identity &> /dev/null; then
    error "Credenciales AWS no configuradas"
    exit 1
fi

log "Iniciando despliegue en región: $REGION"

# 1. Crear tabla DynamoDB
log "Creando tabla DynamoDB..."
aws dynamodb create-table \
    --region $REGION \
    --table-name $TABLE_NAME \
    --attribute-definitions \
        AttributeName=deviceId,AttributeType=S \
        AttributeName=timestamp,AttributeType=N \
    --key-schema \
        AttributeName=deviceId,KeyType=HASH \
        AttributeName=timestamp,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=Project,Value=GPS-Tracking Key=Environment,Value=production

# Esperar a que la tabla esté activa
log "Esperando que la tabla esté activa..."
aws dynamodb wait table-exists --region $REGION --table-name $TABLE_NAME

# Configurar TTL
log "Configurando TTL para la tabla..."
aws dynamodb update-time-to-live \
    --region $REGION \
    --table-name $TABLE_NAME \
    --time-to-live-specification Enabled=true,AttributeName=ttl

# 2. Crear Security Group
log "Creando Security Group..."
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --region $REGION \
    --group-name $SECURITY_GROUP \
    --description "Security group for GPS tracking server" \
    --query 'GroupId' --output text)

# Configurar reglas de Security Group
aws ec2 authorize-security-group-ingress \
    --region $REGION \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --region $REGION \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --region $REGION \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0

log "Security Group creado: $SECURITY_GROUP_ID"

# 3. Crear IAM Role para EC2
log "Creando IAM Role..."
cat > ec2-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

aws iam create-role \
    --role-name GPS-Tracking-EC2-Role \
    --assume-role-policy-document file://ec2-trust-policy.json

# Crear política para DynamoDB
cat > dynamodb-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:Query",
                "dynamodb:Scan",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem"
            ],
            "Resource": "arn:aws:dynamodb:$REGION:*:table/$TABLE_NAME"
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name GPS-Tracking-DynamoDB-Policy \
    --policy-document file://dynamodb-policy.json

# Adjuntar política al rol
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam attach-role-policy \
    --role-name GPS-Tracking-EC2-Role \
    --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/GPS-Tracking-DynamoDB-Policy

# Crear instance profile
aws iam create-instance-profile --instance-profile-name GPS-Tracking-Profile
aws iam add-role-to-instance-profile \
    --instance-profile-name GPS-Tracking-Profile \
    --role-name GPS-Tracking-EC2-Role

log "IAM Role y políticas creadas"

# 4. Crear User Data script para EC2
cat > user-data.sh << 'EOF'
#!/bin/bash
yum update -y
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs git nginx

# Configurar directorio de la aplicación
mkdir -p /opt/gps-tracking
cd /opt/gps-tracking

# Crear package.json
cat > package.json << 'PACKAGE'
{
  "name": "gps-tracking-server",
  "version": "1.0.0",
  "description": "GPS Tracking Server",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "@aws-sdk/client-dynamodb": "^3.450.0",
    "@aws-sdk/lib-dynamodb": "^3.450.0",
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "express-rate-limit": "^7.1.5"
  }
}
PACKAGE

# Instalar dependencias
npm install

# El código del servidor se subirá por separado
# Crear servicio systemd
cat > /etc/systemd/system/gps-tracking.service << 'SERVICE'
[Unit]
Description=GPS Tracking Server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/gps-tracking
ExecStart=/usr/bin/node server.js
Restart=always
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
SERVICE

# Configurar Nginx como proxy reverso
cat > /etc/nginx/conf.d/gps-tracking.conf << 'NGINX'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
NGINX

# Iniciar servicios
systemctl enable nginx
systemctl start nginx
systemctl enable gps-tracking

# Configurar firewall
yum install -y firewalld
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

echo "EC2 setup completado" > /tmp/setup-complete.log
EOF

# 5. Lanzar instancia EC2
log "Lanzando instancia EC2..."
INSTANCE_ID=$(aws ec2 run-instances \
    --region $REGION \
    --image-id ami-0abcdef1234567890 \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP_ID \
    --iam-instance-profile Name=GPS-Tracking-Profile \
    --user-data file://user-data.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=GPS-Tracking-Server},{Key=Project,Value=GPS-Tracking}]' \
    --query 'Instances[0].InstanceId' --output text)

log "Instancia EC2 creada: $INSTANCE_ID"

# Esperar que la instancia esté ejecutándose
log "Esperando que la instancia esté ejecutándose..."
aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCE_ID

# Obtener IP pública
PUBLIC_IP=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

log "IP pública de la instancia: $PUBLIC_IP"

# 6. Crear bucket S3 para el frontend
log "Creando bucket S3 para frontend..."
aws s3 mb s3://$BUCKET_NAME --region $REGION

# Configurar bucket para hosting web estático
aws s3 website s3://$BUCKET_NAME \
    --index-document index.html \
    --error-document error.html

# Configurar política pública para el bucket
cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF

aws s3api put-bucket-policy \
    --bucket $BUCKET_NAME \
    --policy file://bucket-policy.json

log "Bucket S3 creado: $BUCKET_NAME"

# 7. Actualizar configuración del frontend
log "Configurando frontend con URL del servidor..."
sed -i "s|https://tu-servidor-aws.com|http://$PUBLIC_IP|g" frontend/index.html

# Subir frontend a S3
aws s3 sync frontend/ s3://$BUCKET_NAME/ --delete

WEBSITE_URL="http://$BUCKET_NAME.s3-website-$REGION.amazonaws.com"
log "Frontend desplegado en: $WEBSITE_URL"

# 8. Esperar setup completo de EC2 y subir código del servidor
log "Esperando setup completo de EC2..."
sleep 120

# Crear archivo temporal con el código del servidor
cat > temp_server.js << 'SERVERCODE'
// El código del servidor va aquí - se insertará dinámicamente
SERVERCODE

# Subir código del servidor
log "Subiendo código del servidor..."
scp -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no \
    temp_server.js ec2-user@$PUBLIC_IP:/opt/gps-tracking/server.js

# Iniciar el servicio
ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no \
    ec2-user@$PUBLIC_IP "sudo systemctl start gps-tracking"

# Limpiar archivos temporales
rm -f ec2-trust-policy.json dynamodb-policy.json bucket-policy.json user-data.sh temp_server.js

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     DESPLIEGUE COMPLETADO                     ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Servidor API: http://$PUBLIC_IP                               ║"
echo "║  Frontend Web: $WEBSITE_URL"
echo "║  Tabla DynamoDB: $TABLE_NAME                                   ║"
echo "║  Bucket S3: $BUCKET_NAME                                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Próximos pasos:"
echo "1. Configura un dominio personalizado (opcional)"
echo "2. Configura HTTPS con Let's Encrypt"
echo "3. Compila y distribuye la aplicación Android"
echo "4. Configura monitoreo con CloudWatch"


