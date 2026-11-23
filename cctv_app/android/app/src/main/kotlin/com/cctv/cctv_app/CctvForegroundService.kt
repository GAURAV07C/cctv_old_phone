package com.cctv.cctv_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class CctvForegroundService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var currentRoomId: String = "HOME-101"

    companion object {
        const val CHANNEL_ID = "cctv_foreground_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_ROOM_ID = "EXTRA_ROOM_ID"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SmartCCTV:ServiceWakeLock").apply {
            setReferenceCounted(false)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        if (action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        currentRoomId = intent?.getStringExtra(EXTRA_ROOM_ID) ?: currentRoomId

        // Acquire 24-hour WakeLock
        if (wakeLock?.isHeld == false) {
            wakeLock?.acquire(24 * 60 * 60 * 1000L)
        }

        startInForeground(currentRoomId, "CCTV Camera is live & streaming. Room: $currentRoomId")
        return START_STICKY
    }

    // CRITICAL: Called when user swipes away app from Recent Apps!
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // DO NOT stop the service! Keep streaming in background via notification
        startInForeground(currentRoomId, "Protected & Streaming in background. Room: $currentRoomId")

        // Schedule respawn safeguard if system tries to terminate process
        try {
            val restartServiceIntent = Intent(applicationContext, CctvForegroundService::class.java).apply {
                setPackage(packageName)
                action = ACTION_START
                putExtra(EXTRA_ROOM_ID, currentRoomId)
            }
            val restartPendingIntent = PendingIntent.getService(
                applicationContext,
                101,
                restartServiceIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT else PendingIntent.FLAG_ONE_SHOT
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.set(
                AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + 1000,
                restartPendingIntent
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startInForeground(roomId: String, statusText: String) {
        val notificationIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("📹 Smart CCTV Live")
            .setContentText(statusText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Smart CCTV Live Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps CCTV camera running in background"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
