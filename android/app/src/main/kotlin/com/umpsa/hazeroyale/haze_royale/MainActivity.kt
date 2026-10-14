package com.umpsa.hazeroyale.haze_royale

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "haze_royale/hms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isHmsAvailable" -> result.success(isHmsCoreInstalled())
                    else -> result.notImplemented()
                }
            }
    }

    /** True when HMS Core (com.huawei.hwid) is installed, i.e. Huawei kits can work. */
    private fun isHmsCoreInstalled(): Boolean = try {
        packageManager.getPackageInfo("com.huawei.hwid", 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
}
