package com.example.fuel_log

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.location.Location
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.SessionInfo
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarLocation
import androidx.car.app.model.ItemList
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Metadata
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Place
import androidx.car.app.model.PlaceListMapTemplate
import androidx.car.app.model.PlaceMarker
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import org.json.JSONException
import java.time.format.DateTimeParseException
import java.util.Locale

class FuelLogCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        return if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }
    }

    override fun onCreateSession(sessionInfo: SessionInfo): Session = FuelLogSession()
}

private class FuelLogSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        val context = carContext
        if (FuelLocationService.hasCarLocationPermission(context)) {
            FuelLocationService.start(context)
        }
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                FuelLocationService.stop(context)
            }
        })
        return FuelStationsCarScreen(context)
    }
}

private class FuelStationsCarScreen(
    private val context: androidx.car.app.CarContext,
) : Screen(context) {
    private var loading = true
    private var errorMessage: String? = null
    private var stations: List<FuelStation> = emptyList()

    init {
        refresh()
    }

    private fun refresh() {
        loading = true
        errorMessage = null
        if (!FuelLocationService.hasForegroundLocationPermission(context)) {
            showError(
                "Open FuelLog on your phone and allow location access to find nearby fuel stations.",
            )
            return
        }
        if (!FuelLocationService.hasCarLocationPermission(context)) {
            showError(
                "Open FuelLog on your phone and set Location permission to Allow all the time for car searches.",
            )
            return
        }
        FuelStationRepository.findNearby(context) { result ->
            loading = false
            result.onSuccess {
                stations = it
                errorMessage = null
            }.onFailure {
                stations = emptyList()
                errorMessage = it.message ?: "Could not load nearby fuel stations."
            }
            invalidate()
        }
        invalidate()
    }

    private fun showError(message: String) {
        loading = false
        errorMessage = message
    }

    override fun onGetTemplate(): Template {
        if (loading) {
            return PlaceListMapTemplate.Builder()
                .setTitle("Nearby fuel stations")
                .setLoading(true)
                .build()
        }

        val error = errorMessage
        if (error != null) {
            return MessageTemplate.Builder(error)
                .setTitle("FuelLog stations")
                .setHeaderAction(Action.APP_ICON)
                .addAction(
                    Action.Builder()
                        .setTitle("Totals")
                        .setOnClickListener {
                            screenManager.push(FuelTotalsCarScreen(context))
                        }
                        .build(),
                )
                .addAction(
                    Action.Builder()
                        .setTitle("Retry")
                        .setOnClickListener { refresh() }
                        .build(),
                )
                .build()
        }

        val itemList = ItemList.Builder()
        if (stations.isEmpty()) {
            itemList.addItem(
                Row.Builder()
                    .setTitle("No fuel stations found within 10 km")
                    .build(),
            )
        } else {
            stations.take(MAX_VISIBLE_STATIONS).forEachIndexed { index, station ->
                val place = Place.Builder(
                    CarLocation.create(station.latitude, station.longitude),
                ).setMarker(
                    PlaceMarker.Builder().setLabel((index + 1).toString()).build(),
                ).build()
                itemList.addItem(
                    Row.Builder()
                        .setTitle(station.name)
                        .addText(stationRowText(station))
                        .setMetadata(Metadata.Builder().setPlace(place).build())
                        .setOnClickListener {
                            screenManager.push(FuelStationDetailsScreen(context, station))
                        }
                        .build(),
                )
            }
        }
        itemList.addItem(
            Row.Builder()
                .setTitle("© OpenStreetMap contributors")
                .build(),
        )

        return PlaceListMapTemplate.Builder()
            .setTitle("Nearby fuel stations")
            .setHeaderAction(Action.APP_ICON)
            .setCurrentLocationEnabled(true)
            .setItemList(itemList.build())
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Totals")
                            .setOnClickListener {
                                screenManager.push(FuelTotalsCarScreen(context))
                            }
                            .build(),
                    )
                    .addAction(
                        Action.Builder()
                            .setTitle("Refresh")
                            .setOnClickListener { refresh() }
                            .build(),
                    )
                    .build(),
            )
            .build()
    }

    private fun stationRowText(station: FuelStation): String {
        val distance = String.format(
            Locale.US,
            "%.1f mi",
            station.distanceMeters / METERS_PER_MILE,
        )
        return listOf(distance, station.address)
            .filter(String::isNotBlank)
            .joinToString(" · ")
    }

    companion object {
        private const val MAX_VISIBLE_STATIONS = 5
        private const val METERS_PER_MILE = 1609.344
    }
}

private class FuelStationDetailsScreen(
    private val context: androidx.car.app.CarContext,
    private val station: FuelStation,
) : Screen(context) {
    override fun onGetTemplate(): Template {
        val detail = listOf(station.brand, station.address)
            .filter(String::isNotBlank)
            .joinToString(" · ")
            .ifBlank { "Station data © OpenStreetMap contributors" }
        val distance = String.format(
            Locale.US,
            "%.1f mi away",
            station.distanceMeters / METERS_PER_MILE,
        )
        val pane = Pane.Builder()
            .addRow(
                Row.Builder()
                    .setTitle(station.name)
                    .addText(distance)
                    .addText(detail)
                    .build(),
            )
            .addAction(
                Action.Builder()
                    .setTitle("Back to stations")
                    .setOnClickListener { screenManager.pop() }
                    .build(),
            )
            .build()
        return PaneTemplate.Builder(pane)
            .setTitle("Fuel station")
            .setHeaderAction(Action.BACK)
            .build()
    }

    companion object {
        private const val METERS_PER_MILE = 1609.344
    }
}

private class FuelTotalsCarScreen(
    private val context: androidx.car.app.CarContext,
) : Screen(context) {
    override fun onGetTemplate(): Template {
        val totals = try {
            FuelLogTotalsRepository.read(context)
        } catch (error: JSONException) {
            return totalsError()
        } catch (error: DateTimeParseException) {
            return totalsError()
        }
        val pane = Pane.Builder()
            .addRow(totalsRow("This month", totals.currentMonth))
            .addRow(totalsRow("All time", totals.allTime))
            .build()
        return PaneTemplate.Builder(pane)
            .setTitle("FuelLog totals")
            .setHeaderAction(Action.BACK)
            .build()
    }

    private fun totalsRow(title: String, totals: FuelPeriodTotals): Row =
        Row.Builder()
            .setTitle(title)
            .addText(
                String.format(
                    Locale.US,
                    "$%.2f · %.1f gal · %d fills",
                    totals.spent,
                    totals.volume,
                    totals.fills,
                ),
            )
            .addText(
                String.format(
                    Locale.US,
                    "%.1f mi · %s MPG",
                    totals.distance,
                    totals.efficiency?.let { String.format(Locale.US, "%.1f", it) } ?: "—",
                ),
            )
            .build()

    private fun totalsError(): Template =
        MessageTemplate.Builder(
            "FuelLog could not read the saved totals. Open the app on your phone to check your fuel log.",
        )
            .setTitle("FuelLog totals")
            .setHeaderAction(Action.BACK)
            .build()
}
