package com.zeyus.android_multicast_lock

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** AndroidMulticastLockPlugin */
class AndroidMulticastLockPlugin :
    FlutterPlugin,
    MethodCallHandler {
    
    companion object {
        private const val CHANNEL_NAME = "com.zeyus.android_multicast_lock/manage"
        private const val DEFAULT_LOCK_NAME = "com.zeyus.android_multicast_lock"
    }
    // The MethodChannel that will the communication between Flutter and native Android
    //
    // This local reference serves to register the plugin with the Flutter Engine and unregister it
    // when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "acquireMulticastLock" -> {
                try {
                    val isHeld = isMulticastLockHeld()
                    if (!isHeld) {
                        val lockName = call.argument<String>("lockName") ?: DEFAULT_LOCK_NAME
                        acquireMulticastLock(lockName)
                    }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to acquire multicast lock: ${e.message}", null)
                }
            }
            "releaseMulticastLock" -> {
                try {
                    releaseMulticastLock()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to release multicast lock: ${e.message}", null)
                }
            }
            "isMulticastLockHeld" -> {
                val isHeld = isMulticastLockHeld()
                result.success(isHeld)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun acquireMulticastLock(lockName: String = DEFAULT_LOCK_NAME): Boolean {
        val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifiManager.createMulticastLock(lockName)
        multicastLock?.acquire()
        return true
    }

    private fun releaseMulticastLock() {
        multicastLock?.release()
    }

    private fun isMulticastLockHeld(): Boolean {
        return multicastLock?.isHeld ?: false
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
