package com.zeyus.liblsl_test
import android.net.wifi.WifiManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
  private val CHANNEL = "com.zeyus.liblsl_test/Networking"
  private var multicastLock: WifiManager.MulticastLock? = null

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
      call, result ->
      if (call.method == "acquireMulticastLock") {
        try {
          val isHeld = isMulticastLockHeld()
          if (!isHeld) {
            acquireMulticastLock()
          }

          result.success(null)
        } catch (e: Exception) {
          result.error("ERROR", "Failed to acquire multicast lock: ${e.message}", null)
        }
      } else if (call.method == "releaseMulticastLock") {
        try {
          releaseMulticastLock()
          result.success(null)
        } catch (e: Exception) {
          result.error("ERROR", "Failed to release multicast lock: ${e.message}", null)
        }
      } else if (call.method == "isMulticastLockHeld") {
        val isHeld = isMulticastLockHeld()
        result.success(isHeld)
      } else {
        result.notImplemented()
      }
    }
  }

  private fun acquireMulticastLock(): Boolean {
    val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
    multicastLock = wifiManager.createMulticastLock("riseTogether")
    multicastLock?.acquire()
    return true;
  }

  private fun releaseMulticastLock() {
    multicastLock?.release()
  }

  private fun isMulticastLockHeld(): Boolean {
    return multicastLock?.isHeld ?: false
  }


}
