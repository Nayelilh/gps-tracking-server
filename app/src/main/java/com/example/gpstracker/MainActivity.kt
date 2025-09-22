// MainActivity.kt - Actividad principal de la aplicación Android
package com.example.gpstracker

import android.Manifest
import android.content.pm.PackageManager
import android.location.Location
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*
import java.util.*

class MainActivity : AppCompatActivity() {

    companion object {
        private const val SERVER_URL = "https://tu-servidor-aws.com/api/location"
        private const val LOCATION_UPDATE_INTERVAL = 10000L // 10 segundos
        private const val FASTEST_LOCATION_INTERVAL = 5000L // 5 segundos
    }

    // Cliente de localización de Google Play Services
    private lateinit var fusedLocationClient: FusedLocationProviderClient

    // Callback para recibir actualizaciones de ubicación
    private lateinit var locationCallback: LocationCallback

    // Request de configuración para ubicación
    private lateinit var locationRequest: LocationRequest

    // Elementos de la interfaz
    private lateinit var btnStartStop: Button
    private lateinit var txtStatus: TextView
    private lateinit var txtCoordinates: TextView
    private lateinit var txtDeviceId: TextView

    // Variables de estado
    private var isTracking = false
    private lateinit var deviceId: String

    // Cliente HTTP para enviar datos al servidor
    private lateinit var locationSender: LocationSender

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // Inicializar elementos de la interfaz
        initializeViews()

        // Generar ID único para este dispositivo
        deviceId = generateDeviceId()
        txtDeviceId.text = "Device ID: $deviceId"

        // Inicializar cliente de ubicación
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)

        // Inicializar cliente HTTP
        locationSender = LocationSender(SERVER_URL)

        // Configurar request de ubicación
        createLocationRequest()

        // Configurar callback de ubicación
        createLocationCallback()

        // Configurar listener del botón
        btnStartStop.setOnClickListener { toggleTracking() }

        // Verificar permisos al iniciar
        checkLocationPermission()
    }

    /** Inicializa las vistas de la interfaz de usuario */
    private fun initializeViews() {
        btnStartStop = findViewById(R.id.btnStartStop)
        txtStatus = findViewById(R.id.txtStatus)
        txtCoordinates = findViewById(R.id.txtCoordinates)
        txtDeviceId = findViewById(R.id.txtDeviceId)

        txtStatus.text = "Detenido"
        txtCoordinates.text = "Esperando ubicación..."
    }

    /** Genera un ID único para identificar este dispositivo */
    private fun generateDeviceId(): String {
        val prefs = getSharedPreferences("GPS_TRACKER", MODE_PRIVATE)
        var savedId = prefs.getString("device_id", null)

        if (savedId == null) {
            savedId = UUID.randomUUID().toString().substring(0, 8)
            prefs.edit().putString("device_id", savedId).apply()
        }

        return savedId
    }

    /** Configura los parámetros de solicitud de ubicación */
    private fun createLocationRequest() {
        locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            LOCATION_UPDATE_INTERVAL
        )
            .setMinUpdateIntervalMillis(FASTEST_LOCATION_INTERVAL)
            .setMaxUpdateDelayMillis(LOCATION_UPDATE_INTERVAL * 2)
            .build()
    }

    /** Crea el callback que se ejecuta cuando se recibe una nueva ubicación */
    private fun createLocationCallback() {
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                for (location in locationResult.locations) {
                    updateLocationUI(location)
                    sendLocationToServer(location)
                }
            }
        }
    }

    /** Actualiza la interfaz con la nueva ubicación */
    private fun updateLocationUI(location: Location) {
        val coordinates = "Lat: %.6f, Lon: %.6f\nPrecisión: %.1fm".format(
            location.latitude,
            location.longitude,
            location.accuracy
        )

        txtCoordinates.text = coordinates
        android.util.Log.d("GPS_TRACKER", "Nueva ubicación: $coordinates")
    }

    /** Envía la ubicación al servidor AWS */
    private fun sendLocationToServer(location: Location) {
        val locationData = LocationData(
            deviceId,
            System.currentTimeMillis(),
            location.latitude,
            location.longitude,
            location.accuracy,
            android.os.Build.MODEL
        )

        locationSender.sendLocation(locationData, object : LocationSender.Callback {
            override fun onSuccess() {
                runOnUiThread {
                    txtStatus.text = "Activo - Datos enviados"
                    Handler(Looper.getMainLooper()).postDelayed({
                        if (isTracking) {
                            txtStatus.text = "Activo - Rastreando"
                        }
                    }, 2000)
                }
            }

            override fun onError(error: String) {
                runOnUiThread {
                    txtStatus.text = "Activo - Error: $error"
                    android.util.Log.e("GPS_TRACKER", "Error enviando ubicación: $error")
                }
            }
        })
    }

    /** Alterna entre iniciar y detener el tracking */
    private fun toggleTracking() {
        if (isTracking) stopLocationUpdates() else startLocationUpdates()
    }

    /** Inicia las actualizaciones de ubicación */
    private fun startLocationUpdates() {
        if (!checkLocationPermission()) return

        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                mainLooper
            )

            isTracking = true
            btnStartStop.text = "DETENER TRACKING"
            txtStatus.text = "Activo - Rastreando"

            Toast.makeText(this, "Tracking iniciado", Toast.LENGTH_SHORT).show()

        } catch (e: SecurityException) {
            Toast.makeText(this, "Error de permisos", Toast.LENGTH_SHORT).show()
        }
    }

    /** Detiene las actualizaciones de ubicación */
    private fun stopLocationUpdates() {
        fusedLocationClient.removeLocationUpdates(locationCallback)

        isTracking = false
        btnStartStop.text = "INICIAR TRACKING"
        txtStatus.text = "Detenido"
        txtCoordinates.text = "Tracking detenido"

        Toast.makeText(this, "Tracking detenido", Toast.LENGTH_SHORT).show()
    }

    /** Verifica y solicita permisos de ubicación */
    private fun checkLocationPermission(): Boolean {
        return if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissionLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
            false
        } else {
            true
        }
    }

    // Nuevo API para pedir permisos
    private val requestPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                Toast.makeText(this, "Permisos concedidos", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "Permisos necesarios para el funcionamiento", Toast.LENGTH_LONG)
                    .show()
            }
        }

    override fun onPause() {
        super.onPause()
        // No detener el tracking cuando la app va a background
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isTracking) stopLocationUpdates()
    }
}
