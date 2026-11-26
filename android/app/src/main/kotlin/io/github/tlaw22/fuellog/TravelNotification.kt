package io.github.tlaw22.fuellog

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import io.flutter.plugin.common.MethodCall
import kotlin.math.roundToInt

object TravelNotification {
    private const val channelId = "travel_expenses"
    private const val notificationId = 4817
    private const val currentColor = 0xFFFFC300.toInt()
    private const val previousColor = 0xFF003566.toInt()

    data class Data(
        val title: String,
        val firstLabel: String,
        val secondLabel: String,
        val firstAmount: String,
        val secondAmount: String,
        val firstTotal: Double?,
        val secondTotal: Double?,
    ) {
        companion object {
            fun from(call: MethodCall): Data? {
                val title = call.argument<String>("title") ?: return null
                val firstLabel = call.argument<String>("firstLabel") ?: return null
                val secondLabel = call.argument<String>("secondLabel") ?: return null
                val firstAmount = call.argument<String>("firstAmount") ?: return null
                val secondAmount = call.argument<String>("secondAmount") ?: return null
                val firstTotal = call.argument<Double>("firstTotal")
                val secondTotal = call.argument<Double>("secondTotal")
                if ((firstTotal != null && !firstTotal.isFinite()) ||
                    (secondTotal != null && !secondTotal.isFinite())
                ) return null
                return Data(title, firstLabel, secondLabel, firstAmount, secondAmount, firstTotal, secondTotal)
            }
        }
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId)
    }

    fun show(context: Context, data: Data): Boolean {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "Travel expenses", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Custom chart comparison after saving a fill-up"
                },
            )
        }
        if (!manager.areNotificationsEnabled() ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                manager.getNotificationChannel(channelId).importance == NotificationManager.IMPORTANCE_NONE)
        ) return false

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val summary = "${data.firstLabel}: ${data.firstAmount}  |  ${data.secondLabel}: ${data.secondAmount}"
        val notification = builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(data.title)
            .setContentText(summary)
            .setStyle(
                Notification.BigPictureStyle()
                    .setBigContentTitle(data.title)
                    .bigPicture(picture(data))
                    .setSummaryText(summary),
            )
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        manager.notify(notificationId, notification)
        return true
    }

    private fun picture(data: Data): Bitmap {
        val bitmap = Bitmap.createBitmap(600, 240, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        fun text(value: String, x: Float, y: Float, size: Float, color: Int, maxWidth: Float) {
            paint.color = color
            paint.textSize = size
            paint.typeface = android.graphics.Typeface.DEFAULT
            val width = paint.measureText(value)
            if (width > maxWidth) paint.textSize = size * maxWidth / width
            canvas.drawText(value, x, y, paint)
        }
        paint.color = currentColor
        canvas.drawCircle(30f, 50f, 8f, paint)
        text(data.firstLabel, 48f, 58f, 27f, Color.BLACK, 290f)
        text(data.firstAmount, 48f, 92f, 28f, Color.BLACK, 290f)
        paint.color = previousColor
        canvas.drawCircle(30f, 146f, 8f, paint)
        text(data.secondLabel, 48f, 154f, 27f, Color.BLACK, 290f)
        text(data.secondAmount, 48f, 188f, 28f, Color.BLACK, 290f)

        val first = data.firstTotal
        val second = data.secondTotal
        val negative = (first != null && first < 0) || (second != null && second < 0)
        val sum = if (first == null || second == null) 0.0 else first + second
        val share = if (negative || first == null || second == null || sum == 0.0) 0.0 else first / sum
        val bounds = RectF(372f, 28f, 556f, 212f)
        paint.color = previousColor
        canvas.drawCircle(bounds.centerX(), bounds.centerY(), 92f, paint)
        paint.color = currentColor
        canvas.drawArc(bounds, -90f, (share * 360).toFloat(), true, paint)
        paint.color = Color.WHITE
        canvas.drawRoundRect(RectF(393f, 103f, 535f, 137f), 8f, 8f, paint)
        val percent = (share * 100).roundToInt()
        val label = if (negative) "Negative amount" else if (sum == 0.0) "No data" else "$percent% / ${100 - percent}%"
        paint.color = Color.BLACK
        paint.textSize = 23f
        val labelWidth = paint.measureText(label)
        if (labelWidth > 130f) paint.textSize *= 130f / labelWidth
        paint.textAlign = Paint.Align.CENTER
        canvas.drawText(label, bounds.centerX(), 128f, paint)
        return bitmap
    }
}
