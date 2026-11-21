package com.example.fuel_log

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.fuel_log/native",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "androidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                "saveCsv" -> {
                    val name = call.argument<String>("name")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (name == null || bytes == null) {
                        result.error(
                            "invalid_arguments",
                            "A file name and CSV contents are required.",
                            null,
                        )
                    } else {
                        try {
                            result.success(saveCsvToDocuments(name, bytes))
                        } catch (error: Exception) {
                            result.error(
                                "save_failed",
                                error.message ?: "Could not save the CSV file.",
                                null,
                            )
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveCsvToDocuments(name: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = MediaStore.Files.getContentUri("external")
            val uniqueName = nextAvailableName(name) { candidate ->
                contentResolver.query(
                    collection,
                    arrayOf(MediaStore.MediaColumns._ID),
                    "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
                        "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
                    arrayOf(
                        candidate,
                        "${Environment.DIRECTORY_DOCUMENTS}/",
                    ),
                    null,
                )?.use { it.moveToFirst() } ?: false
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, uniqueName)
                put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOCUMENTS}/",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(collection, values)
                ?: throw IOException("Could not create a file in Documents.")
            var published = false
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IOException("Could not open the CSV file for writing.")
                val publishedValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                if (contentResolver.update(uri, publishedValues, null, null) == 0) {
                    throw IOException("Could not finish saving the CSV file.")
                }
                published = true
            } finally {
                if (!published) {
                    contentResolver.delete(uri, null, null)
                }
            }
            return "${Environment.DIRECTORY_DOCUMENTS}/$uniqueName"
        }

        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Storage permission is required to save CSV files.")
        }
        val documents = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOCUMENTS,
        )
        if (!documents.exists() && !documents.mkdirs()) {
            throw IOException("Could not create the Documents folder.")
        }
        val uniqueName = nextAvailableName(name) { File(documents, it).exists() }
        val file = File(documents, uniqueName)
        file.writeBytes(bytes)
        return file.absolutePath
    }

    private fun nextAvailableName(
        name: String,
        exists: (String) -> Boolean,
    ): String {
        val extension = name.substringAfterLast('.', "")
        val base = if (extension.isEmpty()) name else name.substringBeforeLast('.')
        var candidate = name
        var suffix = 1
        while (exists(candidate)) {
            candidate = if (extension.isEmpty()) {
                "$base ($suffix)"
            } else {
                "$base ($suffix).$extension"
            }
            suffix++
        }
        return candidate
    }
}
