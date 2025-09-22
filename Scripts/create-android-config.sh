# ===== create-android-config.sh - Script para configurar app Android =====
#!/bin/bash

echo "Generando configuración para aplicación Android..."

# Variables
SERVER_IP=${1:-"TU_IP_DEL_SERVIDOR"}
OUTPUT_DIR="android-config"

mkdir -p $OUTPUT_DIR

# Crear archivo de configuración
cat > $OUTPUT_DIR/ServerConfig.java << EOF
package com.tuempresa.gpstracker.config;

/**
 * Configuración del servidor para la aplicación GPS Tracker
 * Generado automáticamente por el script de despliegue
 */
public class ServerConfig {
    
    // URL base del servidor API
    public static final String API_BASE_URL = "http://$SERVER_IP:3000/api";
    
    // Endpoints específicos
    public static final String LOCATION_ENDPOINT = API_BASE_URL + "/location";
    public static final String DEVICES_ENDPOINT = API_BASE_URL + "/devices";
    public static final String HEALTH_ENDPOINT = "http://$SERVER_IP:3000/health";
    
    // Configuración de red
    public static final int CONNECTION_TIMEOUT = 10000; // 10 segundos
    public static final int READ_TIMEOUT = 10000; // 10 segundos
    
    // Configuración de GPS
    public static final long LOCATION_UPDATE_INTERVAL = 10000; // 10 segundos
    public static final long FASTEST_LOCATION_INTERVAL = 5000; // 5 segundos
    public static final float MIN_ACCURACY = 50.0f; // metros
    
    // Configuración de reintento
    public static final int MAX_RETRIES = 3;
    public static final long RETRY_DELAY = 2000; // 2 segundos
}
EOF

# Crear archivo de strings para Android
cat > $OUTPUT_DIR/strings.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">GPS Tracker</string>
    <string name="server_url">http://$SERVER_IP:3000</string>
    <string name="api_base_url">http://$SERVER_IP:3000/api</string>
    
    <!-- Mensajes de la aplicación -->
    <string name="permission_location_title">Permisos de Ubicación</string>
    <string name="permission_location_message">Esta aplicación necesita acceso a tu ubicación para funcionar correctamente.</string>
    <string name="tracking_started">Tracking iniciado</string>
    <string name="tracking_stopped">Tracking detenido</string>
    <string name="location_sent">Ubicación enviada</string>
    <string name="connection_error">Error de conexión con el servidor</string>
</resources>
EOF

# Crear archivo build.gradle con configuraciones
cat > $OUTPUT_DIR/build.gradle << EOF
android {
    compileSdk 34
    
    defaultConfig {
        applicationId "com.tuempresa.gpstracker"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
        
        // Configuraciones del servidor
        buildConfigField "String", "SERVER_URL", "\\"http://$SERVER_IP:3000\\""
        buildConfigField "String", "API_BASE_URL", "\\"http://$SERVER_IP:3000/api\\""
    }
    
    buildTypes {
        debug {
            buildConfigField "String", "SERVER_URL", "\\"http://$SERVER_IP:3000\\""
            buildConfigField "boolean", "ENABLE_LOGGING", "true"
        }
        release {
            buildConfigField "String", "SERVER_URL", "\\"http://$SERVER_IP:3000\\""
            buildConfigField "boolean", "ENABLE_LOGGING", "false"
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}

dependencies {
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.9.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    implementation 'com.google.android.gms:play-services-location:21.0.1'
    
    // Networking
    implementation 'com.squareup.okhttp3:okhttp:4.11.0'
    implementation 'com.squareup.retrofit2:retrofit:2.9.0'
    implementation 'com.squareup.retrofit2:converter-gson:2.9.0'
    
    // Testing
    testImplementation 'junit:junit:4.13.2'
    androidTestImplementation 'androidx.test.ext:junit:1.1.5'
}
EOF

echo "Archivos de configuración Android generados en: $OUTPUT_DIR/"
echo ""
echo "Para usar en tu proyecto Android:"
echo "1. Copia ServerConfig.java a src/main/java/com/tuempresa/gpstracker/config/"
echo "2. Reemplaza strings.xml en src/main/res/values/"
echo "3. Actualiza build.gradle con las nuevas configuraciones"