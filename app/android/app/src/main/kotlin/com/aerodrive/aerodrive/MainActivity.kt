package com.aerodrive.aerodrive

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val BOOT_CHANNEL = "com.aerodrive.aerodrive/boot"
    private val SETTINGS_CHANNEL = "com.aerodrive.aerodrive/settings"
    private val BACKUP_SERVICE_CHANNEL = "com.aerodrive.aerodrive/backup_service"

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
    }
}

