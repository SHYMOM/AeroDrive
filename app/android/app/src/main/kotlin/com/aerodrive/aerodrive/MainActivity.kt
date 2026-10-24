package com.aerodrive.aerodrive

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.UiThread
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
    private val BOOT_CHANNEL = "com.aerodrive.aerodrive/boot"
    private val SETTINGS_CHANNEL = "com.aerodrive.aerodrive/settings"
    private val BACKUP_SERVICE_CHANNEL = "com.aerodrive.aerodrive/backup_service"

    companion object {
        private const val FILE_PICKER_CHANNEL = "com.aerodrive.aerodrive/file_picker"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bootCompleted = intent.getBooleanExtra("boot_completed", false)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BOOT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isBootCompleted" -> result.success(bootCompleted)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openManageAllFilesSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                                intent.data = Uri.parse("package:${packageName}")
                                startActivity(intent)
                                result.success(true)
                            } else {
                                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                intent.data = Uri.parse("package:${packageName}")
                                startActivity(intent)
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("INTENT_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Method channel for controlling the foreground backup service
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startBackupService" -> {
                        try {
                            AeroDriveBackupService.start(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }
                    "stopBackupService" -> {
                        try {
                            AeroDriveBackupService.stop(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Method channel for copying content:// URIs to temp directory on background thread.
        // This avoids file_selector's ANR-prone main-thread copy for large files.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_PICKER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copyToTemp" -> {
                        val uriStr = call.argument<String>("uri")
                        val fileName = call.argument<String>("fileName") ?: "temp_file"
                        if (uriStr == null) {
                            result.error("INVALID_ARG", "uri is null", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val uri = Uri.parse(uriStr)
                                val tempDir = File(cacheDir, "aerodrive_picker")
                                tempDir.mkdirs()
                                val tempFile = File(tempDir, fileName)
                                if (tempFile.exists()) {
                                    tempFile.delete()
                                }
                                val inputStream = contentResolver.openInputStream(uri)
                                inputStream?.use { input ->
                                    FileOutputStream(tempFile).use { output ->
                                        val buffer = ByteArray(8192)
                                        var bytesRead: Int
                                        while (input.read(buffer).also { bytesRead = it } != -1) {
                                            output.write(buffer, 0, bytesRead)
                                        }
                                        output.flush()
                                    }
                                }
                                runOnUiThread {
                                    result.success(tempFile.absolutePath)
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("COPY_ERROR", e.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

