package com.example.gpstracker

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

class LocationSender(private val serverUrl: String) {
    private val executor = Executors.newFixedThreadPool(3)

    interface Callback {
        fun onSuccess()
        fun onError(error: String)
    }

    fun sendLocation(locationData: LocationData, callback: Callback) {
        executor.execute {
            try {
                val url = URL(serverUrl)
                val connection = url.openConnection() as HttpURLConnection

                connection.requestMethod = "POST"
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("Accept", "application/json")
                connection.doOutput = true
                connection.connectTimeout = 10000
                connection.readTimeout = 10000

                val jsonData = locationData.toJson()
                connection.outputStream.use { os: OutputStream ->
                    val input = jsonData.toByteArray(StandardCharsets.UTF_8)
                    os.write(input, 0, input.size)
                }

                val responseCode = connection.responseCode
                if (responseCode in 200..299) {
                    callback.onSuccess()
                } else {
                    val errorMsg = readErrorResponse(connection)
                    callback.onError("HTTP $responseCode: $errorMsg")
                }

                connection.disconnect()

            } catch (e: Exception) {
                callback.onError("Error: ${e.message}")
            }
        }
    }

    private fun readErrorResponse(connection: HttpURLConnection): String {
        return try {
            BufferedReader(InputStreamReader(connection.errorStream)).use { reader ->
                val response = StringBuilder()
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    response.append(line)
                }
                response.toString()
            }
        } catch (e: Exception) {
            "Error desconocido"
        }
    }
}
