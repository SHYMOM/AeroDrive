package com.aerodrive.aerodrive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * AeroDriveBackupService
 *
 * A foreground service that keeps the backup watcher alive when the user
 * swipes the app away from recents. This ensures that directory file-system
 * watchers and the periodic sync loop keep running even when the Flutter
 * Activity is destroyed.
 *
 * The service is started by MainActivity when auto-backup is enabled,
 * and stopped when the user explicitly disables auto-backup.
 */
class AeroDriveBackupService : Service() {

    private var flutterEngine: FlutterEngine? = null

    companion object {
        private const val TAG = "AeroDriveBackupService"
        private const val CHANNEL_ID = "aerodrive_backup_channel"
        private const val NOTIFICATION_ID = 1001

        @Volatile
        var activeInstance: AeroDriveBackupService? = null

        fun start(context: Context) {
            val intent = Intent(context, AeroDriveBackupService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.d(TAG, "AeroDriveBackupService start requested")
        }

        fun stop(context: Context) {
            try {
                activeInstance?.flutterEngine?.destroy()
                activeInstance?.flutterEngine = null
                activeInstance?.stopSelf()
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping activeInstance directly", e)
            }
            val intent = Intent(context, AeroDriveBackupService::class.java)
            context.stopService(intent)
            Log.d(TAG, "AeroDriveBackupService stop requested")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        Log.d(TAG, "AeroDriveBackupService created")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())

        try {
            val loader = io.flutter.embedding.engine.loader.FlutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)

            flutterEngine = FlutterEngine(this)
            flutterEngine?.dartExecutor?.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "backgroundMain"
                )
            )
            Log.d(TAG, "Headless Flutter Engine started successfully running backgroundMain")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start headless Flutter Engine", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "AeroDriveBackupService started with startId=$startId")
        // Return STICKY so Android restarts the service if it gets killed
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "AeroDriveBackupService destroyed")
        try {
            flutterEngine?.destroy()
        } catch (e: Exception) {
            Log.e(TAG, "Error destroying flutterEngine", e)
        }
        flutterEngine = null
        if (activeInstance == this) {
            activeInstance = null
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AeroDrive Backup Active")
            .setContentText("Auto-backup is running in the background")
            .setSmallIcon(android.R.drawable.ic_menu_upload)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "AeroDrive Background Backup",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when AeroDrive is performing background backup"
                setShowBadge(false)
            }
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }
}
