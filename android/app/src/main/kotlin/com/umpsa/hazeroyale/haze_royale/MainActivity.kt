package com.umpsa.hazeroyale.haze_royale

import android.content.Intent
import android.content.pm.PackageManager
import com.huawei.hms.common.ApiException
import com.huawei.hms.support.account.AccountAuthManager
import com.huawei.hms.support.account.request.AccountAuthParams
import com.huawei.hms.support.account.request.AccountAuthParamsHelper
import com.huawei.hms.support.account.result.AuthAccount
import com.huawei.hms.support.account.service.AccountAuthService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingSignIn: MethodChannel.Result? = null

    /** HUAWEI ID with the player's nickname; no server-side token is needed. */
    private val accountService: AccountAuthService by lazy {
        val params = AccountAuthParamsHelper(AccountAuthParams.DEFAULT_AUTH_REQUEST_PARAM)
            .setProfile()
            .createParams()
        AccountAuthManager.getService(this, params)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "haze_royale/hms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isHmsAvailable" -> result.success(isHmsCoreInstalled())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "haze_royale/account")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "silentSignIn" -> silentSignIn(result)
                    "signIn" -> signIn(result)
                    "signOut" -> signOut(result)
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

    /** Restores a previous sign-in without showing any UI; null when there is none. */
    private fun silentSignIn(result: MethodChannel.Result) {
        accountService.silentSignIn()
            .addOnSuccessListener { result.success(toMap(it)) }
            .addOnFailureListener { result.success(null) }
    }

    /** Shows the HUAWEI ID sign-in screen; the answer arrives in onActivityResult. */
    private fun signIn(result: MethodChannel.Result) {
        if (pendingSignIn != null) {
            result.error("busy", "Sign-in already in progress", null)
            return
        }
        pendingSignIn = result
        try {
            startActivityForResult(accountService.signInIntent, SIGN_IN_REQUEST)
        } catch (e: Exception) {
            pendingSignIn = null
            result.error("unavailable", e.message, null)
        }
    }

    private fun signOut(result: MethodChannel.Result) {
        accountService.signOut()
            .addOnCompleteListener { result.success(null) }
    }

    @Deprecated("FlutterActivity is not a ComponentActivity, so the result API is not available")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SIGN_IN_REQUEST) return
        val result = pendingSignIn ?: return
        pendingSignIn = null
        val task = AccountAuthManager.parseAuthResultFromIntent(data)
        if (task.isSuccessful) {
            result.success(toMap(task.result))
        } else {
            val code = (task.exception as? ApiException)?.statusCode ?: -1
            result.error(code.toString(), task.exception?.message, null)
        }
    }

    private fun toMap(account: AuthAccount): Map<String, String?> = mapOf(
        "openId" to account.openId,
        "displayName" to account.displayName,
        "avatarUri" to account.avatarUriString,
    )

    private companion object {
        const val SIGN_IN_REQUEST = 8888
    }
}
