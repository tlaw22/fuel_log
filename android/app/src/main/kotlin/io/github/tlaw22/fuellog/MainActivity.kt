package io.github.tlaw22.fuellog

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.content.ContentUris
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.tlaw22.fuellog/native",
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
                "savePumpPhoto" -> {
                    val name = call.argument<String>("name")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (name == null || bytes == null) {
                        result.error(
                            "invalid_arguments",
                            "A photo name and image contents are required.",
                            null,
                        )
                    } else {
                        try {
                            result.success(savePumpPhotoToDocuments(name, bytes))
                        } catch (error: Exception) {
                            result.error(
                                "save_failed",
                                error.message ?: "Could not save the pump photo.",
                                null,
                            )
                        }
                    }
                }
                "listPumpPhotos" -> {
                    try {
                        result.success(listPumpPhotos())
                    } catch (error: Exception) {
                        result.error(
                            "list_failed",
                            error.message ?: "Could not load pump photos.",
                            null,
                        )
                    }
                }
                "readPumpPhoto" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error(
                            "invalid_arguments",
                            "A pump photo identifier is required.",
                            null,
                        )
                    } else {
                        try {
                            result.success(readPumpPhoto(id))
                        } catch (error: Exception) {
                            result.error(
                                "read_failed",
                                error.message ?: "Could not read the pump photo.",
                                null,
                            )
                        }
                    }
                }
                "deletePumpPhoto" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error(
                            "invalid_arguments",
                            "A pump photo identifier is required.",
                            null,
                        )
                    } else {
                        try {
                            result.success(deletePumpPhoto(id))
                        } catch (error: Exception) {
                            result.error(
                                "delete_failed",
                                error.message ?: "Could not delete the pump photo.",
                                null,
                            )
                        }
                    }
                }
                "deleteAllPumpPhotos" -> {
                    try {
                        result.success(deleteAllPumpPhotos())
                    } catch (error: Exception) {
                        result.error(
                            "delete_failed",
                            error.message ?: "Could not delete pump photos.",
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveCsvToDocuments(name: String, bytes: ByteArray): String {
        val relativePath = "${Environment.DIRECTORY_DOCUMENTS}/"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return saveToMediaStore(
                name,
                bytes,
                "text/csv",
                relativePath,
                "a file in Documents",
                "the CSV file",
            )
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

    private fun savePumpPhotoToDocuments(name: String, bytes: ByteArray): String {
        val relativePath = "${Environment.DIRECTORY_DOCUMENTS}/fuel-logs/"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return saveToMediaStore(
                name,
                bytes,
                "image/jpeg",
                relativePath,
                "a photo in Documents/fuel-logs",
                "the pump photo",
            )
        }

        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Storage permission is required to save photos.")
        }
        val documents = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOCUMENTS,
        )
        val photoDirectory = File(documents, "fuel-logs")
        if (!photoDirectory.exists() && !photoDirectory.mkdirs()) {
            throw IOException("Could not create the Documents/fuel-logs folder.")
        }
        val uniqueName = nextAvailableName(name) { File(photoDirectory, it).exists() }
        val file = File(photoDirectory, uniqueName)
        file.writeBytes(bytes)
        return file.absolutePath
    }

    private fun listPumpPhotos(): List<Map<String, String>> {
        requirePhotoStoragePermission()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = MediaStore.Files.getContentUri("external")
            val cursor = contentResolver.query(
                collection,
                arrayOf(
                    MediaStore.MediaColumns._ID,
                    MediaStore.MediaColumns.DISPLAY_NAME,
                ),
                "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND " +
                    "${MediaStore.MediaColumns.MIME_TYPE} LIKE ?",
                arrayOf(pumpPhotoRelativePath(), "image/%"),
                "${MediaStore.MediaColumns.DATE_ADDED} DESC",
            ) ?: throw IOException("Could not query saved pump photos.")
            return cursor.use {
                val idColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameColumn =
                    it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                buildList {
                    while (it.moveToNext()) {
                        val uri = ContentUris.withAppendedId(
                            collection,
                            it.getLong(idColumn),
                        )
                        add(
                            mapOf(
                                "id" to uri.toString(),
                                "name" to it.getString(nameColumn),
                            ),
                        )
                    }
                }
            }
        }

        val directory = pumpPhotoDirectory()
        if (!directory.exists()) return emptyList()
        val files = directory.listFiles()
            ?: throw IOException("Could not read Documents/fuel-logs.")
        return files
            .filter { it.isFile && it.extension.lowercase() in setOf("jpg", "jpeg", "png") }
            .sortedByDescending { it.lastModified() }
            .map { mapOf("id" to it.absolutePath, "name" to it.name) }
    }

    private fun readPumpPhoto(id: String): ByteArray {
        requirePhotoStoragePermission()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val uri = parsePumpPhotoUri(id)
            if (!isSavedPumpPhoto(uri)) {
                throw FileNotFoundException("The selected pump photo no longer exists.")
            }
            return contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IOException("Could not open the selected pump photo.")
        }

        val file = requireLegacyPumpPhoto(id)
        return file.readBytes()
    }

    private fun deletePumpPhoto(id: String): Boolean {
        requirePhotoStoragePermission()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val uri = parsePumpPhotoUri(id)
            if (!isSavedPumpPhoto(uri)) return false
            return contentResolver.delete(
                uri,
                "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND " +
                    "${MediaStore.MediaColumns.MIME_TYPE} LIKE ?",
                arrayOf(pumpPhotoRelativePath(), "image/%"),
            ) == 1
        }

        val file = requireLegacyPumpPhoto(id)
        return file.delete()
    }

    private fun deleteAllPumpPhotos(): Int {
        val photos = listPumpPhotos()
        var deletedCount = 0
        for (photo in photos) {
            val id = photo["id"]
                ?: throw IOException("A saved pump photo has no identifier.")
            if (!deletePumpPhoto(id)) {
                throw IOException("Could not delete saved pump photo $id.")
            }
            deletedCount++
        }
        return deletedCount
    }

    private fun requirePhotoStoragePermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            (checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) !=
                PackageManager.PERMISSION_GRANTED ||
                checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                PackageManager.PERMISSION_GRANTED)
        ) {
            throw SecurityException("Storage permission is required for pump photos.")
        }
    }

    private fun parsePumpPhotoUri(id: String): Uri {
        val uri = Uri.parse(id)
        val collection = MediaStore.Files.getContentUri("external")
        if (uri.scheme != "content" || uri.authority != collection.authority) {
            throw SecurityException("The pump photo identifier is invalid.")
        }
        return uri
    }

    private fun isSavedPumpPhoto(uri: Uri): Boolean {
        val collection = MediaStore.Files.getContentUri("external")
        val cursor = contentResolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns._ID} = ? AND " +
                "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND " +
                "${MediaStore.MediaColumns.MIME_TYPE} LIKE ?",
            arrayOf(
                ContentUris.parseId(uri).toString(),
                pumpPhotoRelativePath(),
                "image/%",
            ),
            null,
        ) ?: throw IOException("Could not verify the selected pump photo.")
        return cursor.use { it.moveToFirst() }
    }

    private fun requireLegacyPumpPhoto(id: String): File {
        val directory = pumpPhotoDirectory().canonicalFile
        val file = File(id).canonicalFile
        if (file.parentFile != directory || !file.isFile ||
            file.extension.lowercase() !in setOf("jpg", "jpeg", "png")
        ) {
            throw FileNotFoundException("The selected pump photo no longer exists.")
        }
        return file
    }

    private fun pumpPhotoDirectory(): File = File(
        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
        "fuel-logs",
    )

    private fun pumpPhotoRelativePath(): String =
        "${Environment.DIRECTORY_DOCUMENTS}/fuel-logs/"

    private fun saveToMediaStore(
        name: String,
        bytes: ByteArray,
        mimeType: String,
        relativePath: String,
        createDescription: String,
        saveDescription: String,
    ): String {
        val collection = MediaStore.Files.getContentUri("external")
        val uniqueName = nextAvailableName(name) { candidate ->
            contentResolver.query(
                collection,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
                    "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
                arrayOf(candidate, relativePath),
                null,
            )?.use { it.moveToFirst() } ?: false
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, uniqueName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values)
            ?: throw IOException("Could not create $createDescription.")
        var published = false
        try {
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IOException("Could not open $saveDescription for writing.")
            val publishedValues = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            if (contentResolver.update(uri, publishedValues, null, null) == 0) {
                throw IOException("Could not finish saving $saveDescription.")
            }
            published = true
        } finally {
            if (!published) {
                contentResolver.delete(uri, null, null)
            }
        }
        return "$relativePath$uniqueName"
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
