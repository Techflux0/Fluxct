package com.io.fluxct

import android.content.res.AssetManager
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class MainActivity : FlutterActivity() {
    // Make sure this matches exactly with your Flutter code
    private val CHANNEL = "com.io.fluxct/emojis"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "Configuring Flutter engine")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                Log.d("MainActivity", "Received method call: ${call.method}")
                
                when (call.method) {
                    "listEmojis" -> handleListEmojis(result)
                    else -> {
                        Log.w("MainActivity", "Unknown method: ${call.method}")
                        result.notImplemented()
                    }
                }
            }
        }
    }

    private fun handleListEmojis(result: MethodChannel.Result) {
        try {
            val emojis = assets.list("emoji")?.toList() ?: emptyList()
            Log.d("MainActivity", "Found ${emojis.size} emojis")
            result.success(emojis)
        } catch (e: IOException) {
            Log.e("MainActivity", "Error listing emojis", e)
            result.error("ASSET_ERROR", "Failed to list emoji files", e.localizedMessage)
        }
    }
}