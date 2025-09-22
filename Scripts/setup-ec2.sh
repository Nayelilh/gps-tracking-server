# ===== setup-ec2.sh - Script para configurar servidor en EC2 =====
#!/bin/bash

echo "Configurando servidor GPS Tracking en EC2..."

# Variables
APP_DIR="/opt/gps-tracking"
SERVICE_USER="ec2-user"

# Crear estructura de directorios
sudo mkdir -p $APP_DIR
sudo chown $SERVICE_USER:$SERVICE_USER $APP_DIR

# Instalar Node.js y npm
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs

# Instalar PM2 para gestión de procesos
sudo npm install -g pm2

# Crear package.json
cat > $APP_DIR/package.json << 'EOF'
{
  "name": "gps-tracking-server",
  "version": "1.0.0",
  "description": "Servidor backend para tracking GPS",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "pm2:start": "pm2 start server.js --name gps-tracking",
    "pm2:stop": "pm2 stop gps-tracking",
    "pm2:restart": "pm2 restart gps-tracking"
  },
  "dependencies": {
    "@aws-sdk/client-dynamodb": "^3.450.0",
    "@aws-sdk/lib-dynamodb": "^3.450.0",
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "express-rate-limit": "^7.1.5"
  },
  "engines": {
    "node": ">=16.0.0"
  }
}
EOF

# Instalar dependencias
cd $APP_DIR
npm install

# Configurar Nginx
sudo yum install -y nginx

cat > /tmp/nginx.conf << 'EOF'
server {
    listen 80;
    server_name _;
    
    # Logs
    access_log /var/log/nginx/gps-tracking-access.log;
    error_log /var/log/nginx/gps-tracking-error.log;

    # Proxy hacia Node.js
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # CORS headers
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
        add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept";
    }
    
    # Health check
    location /health {
        proxy_pass http://localhost:3000;
        access_log off;
    }
    
    # Static files (if any)
    location / {
        root /var/www/html;
        try_files $uri $uri/ =404;
    }
}
EOF

sudo mv /tmp/nginx.conf /etc/nginx/conf.d/gps-tracking.conf
sudo rm -f /etc/nginx/conf.d/default.conf

# Configurar firewall
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# Iniciar servicios
sudo systemctl enable nginx
sudo systemctl start nginx

echo "Configuración de EC2 completada"