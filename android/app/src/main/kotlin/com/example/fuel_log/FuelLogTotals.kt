package com.example.fuel_log

import android.content.Context
import org.json.JSONArray
import org.json.JSONException
import java.time.LocalDate

data class FuelPeriodTotals(
    val fills: Int,
    val spent: Double,
    val volume: Double,
    val distance: Double,
    val efficiency: Double?,
)

data class FuelLogTotals(
    val currentMonth: FuelPeriodTotals,
    val allTime: FuelPeriodTotals,
)

private data class FuelRecord(
    val id: String,
    val date: LocalDate,
    val dateText: String,
    val price: Double,
    val volume: Double,
    val odometer: Double,
) {
    val total: Double
        get() = price * volume
}

object FuelLogTotalsRepository {
    private const val PREFERENCES_FILE = "FlutterSharedPreferences"
    private const val ENTRIES_KEY = "flutter.fuel_entries_v1"

    @Throws(JSONException::class, IllegalArgumentException::class)
    fun read(context: Context): FuelLogTotals {
        val raw = context.getSharedPreferences(
            PREFERENCES_FILE,
            Context.MODE_PRIVATE,
        ).getString(ENTRIES_KEY, null)
        val entries = if (raw.isNullOrBlank()) {
            emptyList()
        } else {
            parseEntries(JSONArray(raw))
        }
        val chronological = entries.sortedWith(
            compareBy<FuelRecord> { it.dateText }.thenBy { it.odometer },
        )
        val distances = mutableMapOf<String, Double>()
        for (index in 1 until chronological.size) {
            val distance = chronological[index].odometer - chronological[index - 1].odometer
            if (distance > 0) {
                distances[chronological[index].id] = distance
            }
        }

        val now = LocalDate.now()
        val monthEntries = chronological.filter {
            it.date.year == now.year && it.date.month == now.month
        }
        return FuelLogTotals(
            currentMonth = summarize(monthEntries, distances),
            allTime = summarize(chronological, distances),
        )
    }

    private fun parseEntries(array: JSONArray): List<FuelRecord> =
        (0 until array.length()).map { index ->
            val json = array.getJSONObject(index)
            val dateText = json.getString("date")
            FuelRecord(
                id = json.getString("id"),
                date = LocalDate.parse(dateText.take(10)),
                dateText = dateText,
                price = json.getDouble("price"),
                volume = json.getDouble("volume"),
                odometer = json.getDouble("odometer"),
            )
        }

    private fun summarize(
        entries: List<FuelRecord>,
        distances: Map<String, Double>,
    ): FuelPeriodTotals {
        var spent = 0.0
        var volume = 0.0
        var distance = 0.0
        var efficiencyVolume = 0.0
        for (entry in entries) {
            spent += entry.total
            volume += entry.volume
            val entryDistance = distances[entry.id]
            if (entryDistance != null) {
                distance += entryDistance
                efficiencyVolume += entry.volume
            }
        }
        return FuelPeriodTotals(
            fills = entries.size,
            spent = spent,
            volume = volume,
            distance = distance,
            efficiency = if (distance > 0 && efficiencyVolume > 0) {
                distance / efficiencyVolume
            } else {
                null
            },
        )
    }
}
