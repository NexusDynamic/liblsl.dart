package com.zeyus.liblsl_timing
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.view.Display
import android.view.Surface
import android.view.SurfaceControl
import android.view.WindowManager
import android.content.Context
import androidx.annotation.RequiresApi
import io.flutter.plugins.GeneratedPluginRegistrant
import kotlin.math.roundToInt

class MainActivity: FlutterActivity() {
  private val CHANNEL = "com.zeyus.liblsl/highrefreshrate"
  private var refreshRatePlugin: AndroidRefreshRatePlugin? = null

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    GeneratedPluginRegistrant.registerWith(flutterEngine)
        
    // Initialize the refresh rate plugin
    refreshRatePlugin = AndroidRefreshRatePlugin(this)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
          "requestHighRefreshRate" -> {
              refreshRatePlugin?.requestHighRefreshRate(result)
          }
          "stopHighRefreshRate" -> {
              refreshRatePlugin?.stopHighRefreshRate(result)
          }
          "getRefreshRateInfo" -> {
              refreshRatePlugin?.getRefreshRateInfo(result)
          }
          else -> {
              result.notImplemented()
          }
      }
    }
  }

}


class AndroidRefreshRatePlugin(private val activity: FlutterActivity) {
    private var originalRefreshRate: Float? = null
    private var highRefreshRateEnabled = false
    private var surfaceControl: SurfaceControl? = null
    
    fun requestHighRefreshRate(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val window = activity.window
                val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    activity.display
                } else {
                    @Suppress("DEPRECATION")
                    window.windowManager.defaultDisplay
                }
                
                if (display != null) {
                    // Store original refresh rate if not already stored
                    if (originalRefreshRate == null) {
                        originalRefreshRate = display.refreshRate
                    }
                    
                    // Find the highest supported refresh rate
                    val supportedModes = display.supportedModes
                    val highestRefreshRate = supportedModes.maxByOrNull { it.refreshRate }
                    
                    if (highestRefreshRate != null) {
                        // Set to highest refresh rate
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val layoutParams = window.attributes
                            layoutParams.preferredDisplayModeId = highestRefreshRate.modeId
                            window.attributes = layoutParams
                        }
                        
                        // For Android 11+ (API 30+), also use Surface.setFrameRate
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val surface = activity.getWindow().getDecorView().getRootView().getRootSurfaceControl()
                            if (surface != null) {
                                try {
                                  if (surfaceControl == null) {
                                    // Create a new SurfaceControl if not already created
                                    surfaceControl = SurfaceControl.Builder()
                                      .setName("HighPrecisionSurface")
                                      .setBufferSize(1, 1)
                                      .build();
                                  }
                                    // Set frame rate with FRAME_RATE_COMPATIBILITY_FIXED_SOURCE
                                    val transaction = SurfaceControl.Transaction()
                                    val framerateTransaction = transaction.setFrameRate(
                                        surfaceControl!!,
                                        highestRefreshRate.refreshRate,
                                        Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE
                                    )
                                    surface.applyTransactionOnDraw(framerateTransaction);
                                } catch (e: Exception) {
                                    // Surface frame rate API might not be available
                                    // Continue with display mode setting only
                                }
                            }
                        }
                        
                        highRefreshRateEnabled = true
                        result.success(true)
                    } else {
                        result.error("NO_HIGH_REFRESH_RATE", "No high refresh rate modes available", null)
                    }
                } else {
                    result.error("NO_DISPLAY", "Could not access display", null)
                }
            } else {
                result.error("UNSUPPORTED", "High refresh rate requires Android M (API 23) or higher", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", "Failed to set high refresh rate: ${e.message}", null)
        }
    }
    
    fun stopHighRefreshRate(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && originalRefreshRate != null) {
                val window = activity.window
                val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    activity.display
                } else {
                    @Suppress("DEPRECATION")
                    window.windowManager.defaultDisplay
                }
                
                if (display != null) {
                    // Find the mode closest to original refresh rate
                    val supportedModes = display.supportedModes
                    val originalMode = supportedModes.minByOrNull { 
                        kotlin.math.abs(it.refreshRate - originalRefreshRate!!) 
                    }
                    
                    if (originalMode != null) {
                        val layoutParams = window.attributes
                        layoutParams.preferredDisplayModeId = originalMode.modeId
                        window.attributes = layoutParams
                        
                        // Reset Surface frame rate for Android 11+
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && surfaceControl != null) {
                            val surface = activity.getWindow().getDecorView().getRootView().getRootSurfaceControl()
                            if (surface != null) {
                                try {
                                  // Set frame rate with FRAME_RATE_COMPATIBILITY_FIXED_SOURCE
                                  val transaction = SurfaceControl.Transaction()
                                  val framerateTransaction = transaction.setFrameRate(
                                      surfaceControl!!,
                                      0f,
                                      Surface.FRAME_RATE_COMPATIBILITY_DEFAULT
                                  )
                                  surface.applyTransactionOnDraw(framerateTransaction);
                                    
                                } catch (e: Exception) {
                                    // Surface frame rate API might not be available
                                }
                            }
                        }
                    }
                }
                
                highRefreshRateEnabled = false
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            result.error("ERROR", "Failed to stop high refresh rate: ${e.message}", null)
        }
    }
    
    fun getRefreshRateInfo(result: MethodChannel.Result) {
        try {
            val info = mutableMapOf<String, Any>()
            
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity.display
            } else {
                @Suppress("DEPRECATION")
                activity.windowManager.defaultDisplay
            }
            
            if (display != null) {
                // Current refresh rate
                info["currentRefreshRate"] = display.refreshRate
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    // Get all supported modes
                    val supportedModes = display.supportedModes
                    val modesList = mutableListOf<Map<String, Any>>()
                    
                    for (mode in supportedModes) {
                        val modeInfo = mapOf(
                            "modeId" to mode.modeId,
                            "width" to mode.physicalWidth,
                            "height" to mode.physicalHeight,
                            "refreshRate" to mode.refreshRate
                        )
                        modesList.add(modeInfo)
                    }
                    
                    info["supportedModes"] = modesList
                    
                    // Find and report the maximum supported refresh rate
                    val maxRefreshRate = supportedModes.maxByOrNull { it.refreshRate }?.refreshRate ?: display.refreshRate
                    info["maximumFramesPerSecond"] = maxRefreshRate.roundToInt()
                    
                    // Current mode info
                    val currentMode = supportedModes.find { it.modeId == display.mode?.modeId }
                    if (currentMode != null) {
                        info["currentMode"] = mapOf(
                            "modeId" to currentMode.modeId,
                            "width" to currentMode.physicalWidth,
                            "height" to currentMode.physicalHeight,
                            "refreshRate" to currentMode.refreshRate
                        )
                    }
                } else {
                    // For older Android versions, just report the current refresh rate
                    info["maximumFramesPerSecond"] = display.refreshRate.roundToInt()
                }
                
                // Report if high refresh rate is currently enabled
                info["highRefreshRateEnabled"] = highRefreshRateEnabled
                
                // Android version info for debugging
                info["androidVersion"] = Build.VERSION.SDK_INT
                info["deviceModel"] = "${Build.MANUFACTURER} ${Build.MODEL}"
                
                result.success(info)
            } else {
                result.error("NO_DISPLAY", "Could not access display information", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", "Failed to get refresh rate info: ${e.message}", null)
        }
    }
}
