package io.github.tlaw22.fuellog

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.ContentUris
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val bluetoothExecutor = Executors.newSingleThreadExecutor()
    private val bluetoothLock = Any()
    private var bluetoothTransferGeneration = 0L

    @Volatile
    private var bluetoothServerSocket: BluetoothServerSocket? = null

    @Volatile
    private var bluetoothSocket: BluetoothSocket? = null

    private val bluetoothServiceUuid =
        UUID.fromString("53796e63-4675-4c6f-6742-426c4c6f6701")
    private val maxBluetoothPayloadBytes = 32 * 1024 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.tlaw22.fuellog/native",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "androidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                "listPairedBluetoothDevices" -> listPairedBluetoothDevices(result)
                "openBluetoothSettings" -> openBluetoothSettings(result)
                "startBluetoothServer" -> {
                    val address = call.argument<String>("address")
                    if (address == null) {
                        result.error(
                            "invalid_arguments",
                            "A paired phone address is required.",
                            null,
                        )
                    } else {
                        startBluetoothServer(address, result)
                    }
                }
                "connectBluetoothDevice" -> {
                    val address = call.argument<String>("address")
                    if (address == null) {
                        result.error(
                            "invalid_arguments",
                            "A paired phone address is required.",
                            null,
                        )
                    } else {
                        connectBluetoothDevice(address, result)
                    }
                }
                "sendBluetoothData" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error(
                            "invalid_arguments",
                            "Bluetooth transfer data is required.",
                            null,
                        )
                    } else {
                        sendBluetoothData(bytes, result)
                    }
                }
                "receiveBluetoothData" -> receiveBluetoothData(result)
                "closeBluetoothTransfer" -> closeBluetoothTransfer(result)
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
                "saveTextReport" -> {
                    val name = call.argument<String>("name")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (name == null || bytes == null) {
                        result.error(
                            "invalid_arguments",
                            "A file name and report contents are required.",
                            null,
                        )
                    } else {
                        try {
                            result.success(saveTextReportToDocuments(name, bytes))
                        } catch (error: Exception) {
                            result.error(
                                "save_failed",
                                error.message ?: "Could not save the text report.",
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
                "deleteAllTextReports" -> {
                    try {
                        result.success(deleteAllTextReports())
                    } catch (error: Exception) {
                        result.error(
                            "delete_failed",
                            error.message ?: "Could not delete text reports.",
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun listPairedBluetoothDevices(result: MethodChannel.Result) {
        try {
            val devices = requireBluetoothAdapter().bondedDevices
                .sortedBy { it.name ?: it.address }
                .map {
                    mapOf(
                        "name" to (it.name ?: "Unknown phone"),
                        "address" to it.address,
                    )
                }
            result.success(devices)
        } catch (error: Exception) {
            result.error(
                "bluetooth_devices_failed",
                error.message ?: "Could not read paired Bluetooth phones.",
                null,
            )
        }
    }

    private fun openBluetoothSettings(result: MethodChannel.Result) {
        try {
            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            result.success(null)
        } catch (error: Exception) {
            result.error(
                "bluetooth_settings_failed",
                error.message ?: "Could not open Bluetooth settings.",
                null,
            )
        }
    }

    private fun requireBluetoothAdapter(): BluetoothAdapter {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Bluetooth permission is required.")
        }
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            ?: throw IllegalStateException("Bluetooth is not supported on this phone.")
        val adapter = manager.adapter
            ?: throw IllegalStateException("Bluetooth is not supported on this phone.")
        if (!adapter.isEnabled) {
            throw IllegalStateException("Turn on Bluetooth to continue.")
        }
        return adapter
    }

    private fun requireBondedDevice(address: String) =
        requireBluetoothAdapter().getRemoteDevice(address).also {
            if (it.bondState != BluetoothDevice.BOND_BONDED) {
                throw SecurityException("The selected phone is no longer paired.")
            }
        }

    private fun startBluetoothServer(
        expectedAddress: String,
        result: MethodChannel.Result,
    ) {
        val generation = synchronized(bluetoothLock) {
            ++bluetoothTransferGeneration
            bluetoothTransferGeneration
        }
        bluetoothExecutor.execute {
            var serverSocket: BluetoothServerSocket? = null
            try {
                requireBondedDevice(expectedAddress)
                val server = requireBluetoothAdapter()
                    .listenUsingRfcommWithServiceRecord(
                        "FuelLog",
                        bluetoothServiceUuid,
                    )
                serverSocket = server
                synchronized(bluetoothLock) {
                    if (generation != bluetoothTransferGeneration) {
                        throw IOException("The Bluetooth transfer was cancelled.")
                    }
                    bluetoothServerSocket = server
                }
                val socket = server.accept()
                if (!socket.remoteDevice.address.equals(
                        expectedAddress,
                        ignoreCase = true,
                    )
                ) {
                    socket.close()
                    throw SecurityException("A different paired phone connected.")
                }
                synchronized(bluetoothLock) {
                    if (bluetoothServerSocket === server) {
                        bluetoothServerSocket = null
                    }
                    bluetoothSocket = socket
                }
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                synchronized(bluetoothLock) {
                    if (bluetoothServerSocket === serverSocket) {
                        bluetoothServerSocket = null
                    }
                }
                runOnUiThread {
                    result.error(
                        "bluetooth_server_failed",
                        error.message ?: "Could not receive a Bluetooth connection.",
                        null,
                    )
                }
            } finally {
                closeBluetoothResource(serverSocket, "Bluetooth server")
            }
        }
    }

    private fun connectBluetoothDevice(
        address: String,
        result: MethodChannel.Result,
    ) {
        val generation = synchronized(bluetoothLock) {
            ++bluetoothTransferGeneration
            bluetoothTransferGeneration
        }
        bluetoothExecutor.execute {
            var socket: BluetoothSocket? = null
            try {
                val device = requireBondedDevice(address)
                val connection = device.createRfcommSocketToServiceRecord(
                    bluetoothServiceUuid,
                )
                socket = connection
                synchronized(bluetoothLock) {
                    if (generation != bluetoothTransferGeneration) {
                        throw IOException("The Bluetooth transfer was cancelled.")
                    }
                    bluetoothSocket = connection
                }
                connection.connect()
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                synchronized(bluetoothLock) {
                    if (bluetoothSocket === socket) bluetoothSocket = null
                }
                closeBluetoothResource(socket, "Bluetooth connection")
                runOnUiThread {
                    result.error(
                        "bluetooth_connect_failed",
                        error.message ?: "Could not connect to the paired phone.",
                        null,
                    )
                }
            }
        }
    }

    private fun sendBluetoothData(
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (bytes.isEmpty() || bytes.size > maxBluetoothPayloadBytes) {
            result.error(
                "invalid_payload",
                "Bluetooth transfer data must be between 1 byte and 32 MB.",
                null,
            )
            return
        }
        bluetoothExecutor.execute {
            try {
                val socket = synchronized(bluetoothLock) { bluetoothSocket }
                    ?: throw IllegalStateException("No Bluetooth phone is connected.")
                val output = DataOutputStream(socket.outputStream)
                output.writeInt(bytes.size)
                output.write(bytes)
                output.flush()
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "bluetooth_send_failed",
                        error.message ?: "Could not send Bluetooth data.",
                        null,
                    )
                }
            }
        }
    }

    private fun receiveBluetoothData(result: MethodChannel.Result) {
        bluetoothExecutor.execute {
            try {
                val socket = synchronized(bluetoothLock) { bluetoothSocket }
                    ?: throw IllegalStateException("No Bluetooth phone is connected.")
                val input = DataInputStream(socket.inputStream)
                val size = input.readInt()
                if (size < 1 || size > maxBluetoothPayloadBytes) {
                    throw IOException("The received Bluetooth file has an invalid size.")
                }
                val bytes = ByteArray(size)
                input.readFully(bytes)
                runOnUiThread { result.success(bytes) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "bluetooth_receive_failed",
                        error.message ?: "Could not receive Bluetooth data.",
                        null,
                    )
                }
            }
        }
    }

    private fun closeBluetoothTransfer(result: MethodChannel.Result) {
        val resources = synchronized(bluetoothLock) {
            bluetoothTransferGeneration++
            val current = bluetoothServerSocket to bluetoothSocket
            bluetoothServerSocket = null
            bluetoothSocket = null
            current
        }
        val failures = mutableListOf<String>()
        try {
            resources.first?.close()
        } catch (error: IOException) {
            failures.add(error.message ?: "Could not stop the Bluetooth listener.")
        }
        try {
            resources.second?.close()
        } catch (error: IOException) {
            failures.add(error.message ?: "Could not close the Bluetooth connection.")
        }
        if (failures.isEmpty()) {
            result.success(null)
        } else {
            result.error("bluetooth_close_failed", failures.joinToString(" "), null)
        }
    }

    private fun closeBluetoothResource(resource: Closeable?, description: String) {
        try {
            resource?.close()
        } catch (error: IOException) {
            android.util.Log.w(
                "FuelLogBluetooth",
                "Could not close $description: ${error.message}",
            )
        }
    }

    override fun onDestroy() {
        val resources = synchronized(bluetoothLock) {
            bluetoothTransferGeneration++
            val current = bluetoothServerSocket to bluetoothSocket
            bluetoothServerSocket = null
            bluetoothSocket = null
            current
        }
        closeBluetoothResource(resources.first, "Bluetooth server")
        closeBluetoothResource(resources.second, "Bluetooth connection")
        bluetoothExecutor.shutdownNow()
        super.onDestroy()
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

    private fun saveTextReportToDocuments(name: String, bytes: ByteArray): String {
        val relativePath = "${Environment.DIRECTORY_DOCUMENTS}/"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return saveToMediaStore(
                name,
                bytes,
                "text/plain",
                relativePath,
                "a text report in Documents",
                "the text report",
            )
        }

        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Storage permission is required to save reports.")
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

    private fun deleteAllTextReports(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = MediaStore.Files.getContentUri("external")
            val cursor = contentResolver.query(
                collection,
                arrayOf(
                    MediaStore.MediaColumns._ID,
                    MediaStore.MediaColumns.DISPLAY_NAME,
                ),
                "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND " +
                    "${MediaStore.MediaColumns.MIME_TYPE} = ?",
                arrayOf(
                    "${Environment.DIRECTORY_DOCUMENTS}/",
                    "text/plain",
                ),
                null,
            ) ?: throw IOException("Could not query saved text reports.")
            val reports = cursor.use {
                val idColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameColumn =
                    it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                buildList {
                    while (it.moveToNext()) {
                        val name = it.getString(nameColumn)
                        if (name.startsWith("fuel_log_report_") &&
                            name.endsWith(".txt", ignoreCase = true)
                        ) {
                            add(
                                ContentUris.withAppendedId(
                                    collection,
                                    it.getLong(idColumn),
                                ) to name,
                            )
                        }
                    }
                }
            }
            var deletedCount = 0
            for ((uri, name) in reports) {
                val deleted = contentResolver.delete(
                    uri,
                    "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND " +
                        "${MediaStore.MediaColumns.MIME_TYPE} = ?",
                    arrayOf(
                        "${Environment.DIRECTORY_DOCUMENTS}/",
                        "text/plain",
                    ),
                )
                if (deleted != 1) {
                    throw IOException("Could not delete report $name.")
                }
                deletedCount++
            }
            return deletedCount
        }

        val documents = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOCUMENTS,
        )
        if (!documents.exists()) return 0
        val files = documents.listFiles()
            ?: throw IOException("Could not read the Documents folder.")
        var deletedCount = 0
        for (file in files) {
            if (file.isFile && file.name.startsWith("fuel_log_report_") &&
                file.extension.equals("txt", ignoreCase = true)
            ) {
                if (!file.delete()) {
                    throw IOException("Could not delete report ${file.name}.")
                }
                deletedCount++
            }
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
