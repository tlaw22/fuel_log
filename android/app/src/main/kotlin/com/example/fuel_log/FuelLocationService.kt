package com.example.fuel_log

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat

class FuelLocationService : Service() {
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            saveLocation(this@FuelLocationService, location)
        }

        override fun onProviderEnabled(provider: String) = Unit

        override fun onProviderDisabled(provider: String) = Unit
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            createNotificationChannel()
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: IllegalStateException) {
            Log.e(TAG, "Android would not start FuelLog's location service.", error)
            stopSelf(startId)
            return START_NOT_STICKY
        } catch (error: SecurityException) {
            Log.e(TAG, "Location permission is required for FuelLog's car screen.", error)
            stopSelf(startId)
            return START_NOT_STICKY
        }
        requestLocationUpdates()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        locationManager.removeUpdates(listener)
        super.onDestroy()
    }

    private fun requestLocationUpdates() {
        if (!hasForegroundLocationPermission(this)) {
            stopSelf()
            return
        }
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = manager.getProviders(true).filter {
            it == LocationManager.NETWORK_PROVIDER || it == LocationManager.GPS_PROVIDER
        }
        try {
            for (provider in providers) {
                manager.requestLocationUpdates(
                    provider,
                    LOCATION_UPDATE_INTERVAL_MS,
                    LOCATION_UPDATE_DISTANCE_METERS,
                    listener,
                    Looper.getMainLooper(),
                )
            }
        } catch (error: SecurityException) {
            Log.e(TAG, "Location permission was revoked while FuelLog was connected to a car.", error)
            stopSelf()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "FuelLog car location",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("FuelLog")
            .setContentText("Finding nearby fuel stations")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    companion object {
        private const val TAG = "FuelLocationService"
        private const val CHANNEL_ID = "fuel_log_car_location"
        private const val NOTIFICATION_ID = 2481
        private const val LOCATION_UPDATE_INTERVAL_MS = 15000L
        private const val LOCATION_UPDATE_DISTANCE_METERS = 50f
        private const val LOCATION_PREFS = "fuel_log_car_location"
        private const val MAX_LOCATION_AGE_MS = 5 * 60 * 1000L

        fun hasForegroundLocationPermission(context: Context): Boolean =
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ) == PackageManager.PERMISSION_GRANTED

        fun hasCarLocationPermission(context: Context): Boolean {
            if (!hasForegroundLocationPermission(context)) return false
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_BACKGROUND_LOCATION,
                ) == PackageManager.PERMISSION_GRANTED
        }

        fun start(context: Context): Boolean {
            if (!hasCarLocationPermission(context)) return false
            val intent = Intent(context, FuelLocationService::class.java)
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (error: IllegalStateException) {
                Log.e(TAG, "Android blocked the car location service from starting.", error)
                false
            } catch (error: SecurityException) {
                Log.e(TAG, "Location permission is required for the car location service.", error)
                false
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, FuelLocationService::class.java))
        }

        fun readSavedLocation(context: Context): Location? {
            val preferences =
                context.getSharedPreferences(LOCATION_PREFS, Context.MODE_PRIVATE)
            val timestamp = preferences.getLong("timestamp", 0L)
            val age = System.currentTimeMillis() - timestamp
            if (age !in 0..MAX_LOCATION_AGE_MS) return null
            val latitude = preferences.getString("latitude", null)?.toDoubleOrNull()
                ?: return null
            val longitude = preferences.getString("longitude", null)?.toDoubleOrNull()
                ?: return null
            return Location("FuelLog").apply {
                this.latitude = latitude
                this.longitude = longitude
                time = timestamp
            }
        }

        fun saveLocation(context: Context, location: Location) {
            context.getSharedPreferences(LOCATION_PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString("latitude", location.latitude.toString())
                .putString("longitude", location.longitude.toString())
                .putLong("timestamp", location.time)
                .apply()
        }
    }
}
