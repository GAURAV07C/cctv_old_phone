package com.cctv.cctv_app

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.cctv/foreground_service"

    // Keep Flutter Engine alive even if Activity is stopped/swiped
    override fun shouldDestroyEngineWithHost(): Boolean {
        return false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val roomId = call.argument<String>("roomId") ?: "HOME-101"
                    val serviceIntent = Intent(this, CctvForegroundService::class.java).apply {
                        action = CctvForegroundService.ACTION_START
                        putExtra(CctvForegroundService.EXTRA_ROOM_ID, roomId)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success(true)
                }
                "stopService" -> {
                    val serviceIntent = Intent(this, CctvForegroundService::class.java).apply {
                        action = CctvForegroundService.ACTION_STOP
                    }
                    startService(serviceIntent)
                    result.success(true)
                }
                "moveToBackground" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
