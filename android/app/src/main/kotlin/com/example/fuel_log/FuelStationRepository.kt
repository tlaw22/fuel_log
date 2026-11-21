package com.example.fuel_log

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.concurrent.Executors

data class FuelStation(
    val id: String,
    val name: String,
    val brand: String,
    val address: String,
    val latitude: Double,
    val longitude: Double,
    val distanceMeters: Float,
) {
    fun toChannelMap(): Map<String, Any> = mapOf(
        "id" to id,
        "name" to name,
        "brand" to brand,
        "address" to address,
        "latitude" to latitude,
        "longitude" to longitude,
        "distanceMeters" to distanceMeters.toDouble(),
    )
}

class StationSearchException(val code: String, message: String) : Exception(message)

object FuelStationRepository {
    private const val OVERPASS_URL = "https://overpass-api.de/api/interpreter"
    private const val SEARCH_RADIUS_METERS = 10000
    private const val MAX_RESULTS = 20
    private const val MAX_LOCATION_AGE_MS = 5 * 60 * 1000L
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun findNearby(
        context: Context,
        callback: (Result<List<FuelStation>>) -> Unit,
    ) {
        if (!hasLocationPermission(context)) {
            deliver(
                callback,
                Result.failure(
                    StationSearchException(
                        "location_permission_required",
                        "Allow location access in FuelLog before searching for stations.",
                    ),
                ),
            )
            return
        }

        val locationManager =
            context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val location = try {
            listOfNotNull(
                FuelLocationService.readSavedLocation(context),
                findRecentDeviceLocation(locationManager),
            ).maxByOrNull(Location::getTime)
        } catch (error: SecurityException) {
            deliver(callback, Result.failure(error))
            return
        }

        if (location != null) {
            searchAt(location, callback)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            deliver(
                callback,
                Result.failure(
                    StationSearchException(
                        "location_unavailable",
                        "The phone has no recent location. Open FuelLog and try again.",
                    ),
                ),
            )
            return
        }

        val provider = enabledProvider(locationManager)
        if (provider == null) {
            deliver(
                callback,
                Result.failure(
                    StationSearchException(
                        "location_unavailable",
                        "Turn on location services and try again.",
                    ),
                ),
            )
            return
        }

        try {
            locationManager.getCurrentLocation(
                provider,
                CancellationSignal(),
                context.mainExecutor,
            ) { currentLocation ->
                if (currentLocation == null) {
                    deliver(
                        callback,
                        Result.failure(
                            StationSearchException(
                                "location_unavailable",
                                "The phone could not determine its current location.",
                            ),
                        ),
                    )
                } else {
                    FuelLocationService.saveLocation(context, currentLocation)
                    searchAt(currentLocation, callback)
                }
            }
        } catch (error: SecurityException) {
            deliver(callback, Result.failure(error))
        }
    }

    private fun hasLocationPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED

    private fun findRecentDeviceLocation(manager: LocationManager): Location? =
        manager.getProviders(true)
            .mapNotNull { provider -> manager.getLastKnownLocation(provider) }
            .filter { location ->
                val age = System.currentTimeMillis() - location.time
                age in 0..MAX_LOCATION_AGE_MS
            }
            .maxByOrNull(Location::getTime)

    private fun enabledProvider(manager: LocationManager): String? =
        listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
            .firstOrNull { provider ->
                manager.isProviderEnabled(provider)
            }

    private fun searchAt(
        location: Location,
        callback: (Result<List<FuelStation>>) -> Unit,
    ) {
        worker.execute {
            val result = try {
                Result.success(queryOverpass(location))
            } catch (error: IOException) {
                Result.failure(
                    StationSearchException(
                        "station_search_failed",
                        "Could not reach OpenStreetMap. Check your connection and try again.",
                    ).also { it.initCause(error) },
                )
            } catch (error: JSONException) {
                Result.failure(
                    StationSearchException(
                        "invalid_station_data",
                        "OpenStreetMap returned station data that FuelLog could not read.",
                    ).also { it.initCause(error) },
                )
            }
            deliver(callback, result)
        }
    }

    private fun queryOverpass(location: Location): List<FuelStation> {
        val latitude = String.format(Locale.US, "%.6f", location.latitude)
        val longitude = String.format(Locale.US, "%.6f", location.longitude)
        val query = """
            [out:json][timeout:20];
            (
              node["amenity"="fuel"](around:$SEARCH_RADIUS_METERS,$latitude,$longitude);
              way["amenity"="fuel"](around:$SEARCH_RADIUS_METERS,$latitude,$longitude);
              relation["amenity"="fuel"](around:$SEARCH_RADIUS_METERS,$latitude,$longitude);
            );
            out center tags;
        """.trimIndent()

        val connection = URL(OVERPASS_URL).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 15000
            connection.readTimeout = 20000
            connection.doOutput = true
            connection.setRequestProperty(
                "Content-Type",
                "application/x-www-form-urlencoded; charset=UTF-8",
            )
            connection.setRequestProperty("User-Agent", "FuelLog/1.0 (Android)")
            val encodedQuery = URLEncoder.encode(query, StandardCharsets.UTF_8.name())
            connection.outputStream.bufferedWriter(StandardCharsets.UTF_8).use {
                it.write("data=$encodedQuery")
            }

            val status = connection.responseCode
            val stream = if (status in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream
                    ?: throw IOException("OpenStreetMap returned HTTP $status.")
            }
            val response = stream.bufferedReader(StandardCharsets.UTF_8).use {
                it.readText()
            }
            if (status !in 200..299) {
                throw IOException("OpenStreetMap returned HTTP $status: $response")
            }
            return parseStations(JSONObject(response), location)
        } finally {
            connection.disconnect()
        }
    }

    private fun parseStations(
        response: JSONObject,
        origin: Location,
    ): List<FuelStation> {
        val elements = response.getJSONArray("elements")
        val stations = ArrayList<FuelStation>()
        for (index in 0 until elements.length()) {
            val element = elements.getJSONObject(index)
            val tags = element.optJSONObject("tags") ?: continue
            val center = element.optJSONObject("center")
            val latitude = if (element.has("lat")) {
                element.getDouble("lat")
            } else {
                val value = center?.optDouble("lat", Double.NaN) ?: continue
                if (!value.isFinite()) continue
                value
            }
            val longitude = if (element.has("lon")) {
                element.getDouble("lon")
            } else {
                val value = center?.optDouble("lon", Double.NaN) ?: continue
                if (!value.isFinite()) continue
                value
            }
            val brand = tags.optString("brand").trim()
            val name = sequenceOf(
                tags.optString("name").trim(),
                brand,
                tags.optString("operator").trim(),
            ).firstOrNull(String::isNotBlank) ?: "Fuel station"
            val address = listOf(
                listOf(
                    tags.optString("addr:street").trim(),
                    tags.optString("addr:housenumber").trim(),
                ).filter(String::isNotBlank).joinToString(" "),
                tags.optString("addr:city").trim(),
            ).filter(String::isNotBlank).joinToString(", ")
            val result = FloatArray(1)
            Location.distanceBetween(
                origin.latitude,
                origin.longitude,
                latitude,
                longitude,
                result,
            )
            stations.add(
                FuelStation(
                    id = "${element.optString("type")}/${element.getLong("id")}",
                    name = name,
                    brand = brand,
                    address = address,
                    latitude = latitude,
                    longitude = longitude,
                    distanceMeters = result[0],
                ),
            )
        }
        return stations
            .distinctBy(FuelStation::id)
            .sortedBy(FuelStation::distanceMeters)
            .take(MAX_RESULTS)
    }

    private fun deliver(
        callback: (Result<List<FuelStation>>) -> Unit,
        result: Result<List<FuelStation>>,
    ) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            callback(result)
        } else {
            mainHandler.post { callback(result) }
        }
    }
}
