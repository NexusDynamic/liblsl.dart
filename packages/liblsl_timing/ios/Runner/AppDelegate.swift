import Flutter
import UIKit

// Create a separate plugin class for better architecture
public class AppleRefreshRatePlugin: NSObject, FlutterPlugin {
    private var displayLink: CADisplayLink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.zeyus.liblsl/highrefreshrate",
            binaryMessenger: registrar.messenger()
        )
        let instance = AppleRefreshRatePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestHighRefreshRate":
            requestHighRefreshRate(result: result)
        case "stopHighRefreshRate":
            stopHighRefreshRate(result: result)
        case "getRefreshRateInfo":
            getRefreshRateInfo(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func requestHighRefreshRate(result: @escaping FlutterResult) {
        // Stop any existing display link
        displayLink?.invalidate()
        
        // Create new display link
        displayLink = CADisplayLink(target: self, selector: #selector(displayCallback))
        
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: 120,
                maximum: 120,
                preferred: 120
            )
        } else {
            displayLink?.preferredFramesPerSecond = 120
        }
        
        displayLink?.add(to: .main, forMode: .default)
        result(true)
    }
    
    private func stopHighRefreshRate(result: @escaping FlutterResult) {
        displayLink?.invalidate()
        displayLink = nil
        result(true)
    }
    
    private func getRefreshRateInfo(result: @escaping FlutterResult) {
        var info: [String: Any] = [:]
        
        if #available(iOS 10.3, *) {
            let mainScreen = UIScreen.main
            info["maximumFramesPerSecond"] = mainScreen.maximumFramesPerSecond
            
            if let displayLink = displayLink {
                info["currentFramesPerSecond"] = 1.0 / (displayLink.targetTimestamp - displayLink.timestamp)
                info["duration"] = displayLink.duration
                info["timestamp"] = displayLink.timestamp
                info["targetTimestamp"] = displayLink.targetTimestamp
                
                if #available(iOS 15.0, *) {
                    info["preferredFrameRateRange"] = [
                        "minimum": displayLink.preferredFrameRateRange.minimum,
                        "maximum": displayLink.preferredFrameRateRange.maximum,
                        "preferred": displayLink.preferredFrameRateRange.preferred
                    ]
                }
            }
        }
        
        result(info)
    }
    
    @objc private func displayCallback(_ displayLink: CADisplayLink) {
        // This callback is called on each frame
        // You can use this to track frame timing if needed
    }
}

// Simplified AppDelegate
@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Register our custom plugin
        AppleRefreshRatePlugin.register(with: self.registrar(forPlugin: "AppleRefreshRatePlugin")!)
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
