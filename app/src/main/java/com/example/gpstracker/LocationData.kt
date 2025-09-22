package com.example.gpstracker

data class LocationData(
    val deviceId: String,
    val timestamp: Long,
    val latitude: Double,
    val longitude: Double,
    val accuracy: Float,
    val deviceName: String
) {
    fun toJson(): String {
        return """{
            "deviceId":"$deviceId",
            "timestamp":$timestamp,
            "latitude":$latitude,
            "longitude":$longitude,
            "accuracy":$accuracy,
            "deviceName":"$deviceName"
        }""".trimIndent()
    }
}
