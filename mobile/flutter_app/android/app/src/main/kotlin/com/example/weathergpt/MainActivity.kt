package com.example.weathergpt

import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "weathergpt/local_ai"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copyBundledModel" -> {
                        val assetPath = call.argument<String>("assetPath")
                        val targetName = call.argument<String>("targetName")
                        if (assetPath == null || targetName == null) {
                            result.error(
                                "INVALID_ARGS",
                                "assetPath and targetName are required",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val target = copyBundledAsset(assetPath, targetName)
                            result.success(target.absolutePath)
                        } catch (e: Exception) {
                            result.error("COPY_FAILED", e.message, null)
                        }
                    }
                    "modelPath" -> {
                        // Single source of truth for the extracted model path.
                        val targetName = call.argument<String>("targetName")
                        if (targetName == null) {
                            result.error("INVALID_ARGS", "targetName is required", null)
                            return@setMethodCallHandler
                        }
                        val target = File(filesDir, targetName)
                        result.success(
                            if (target.exists() && target.length() > 0L) target.absolutePath else null,
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Streams a Flutter-bundled asset into app-private storage (Context.getFilesDir()).
     *
     * The GGUF model is ~769 MB — it is copied in 1 MiB chunks so it never
     * enters the Java heap (rootBundle.load in Dart would allocate the whole
     * file at once and OOM on 4 GB phones).
     */
    private fun copyBundledAsset(assetPath: String, targetName: String): File {
        val target = File(filesDir, targetName)
        if (target.exists() && target.length() > 0L) return target

        // Flutter assets live under flutter_assets/ inside the APK; the
        // flutter loader resolves the correct key for debug and release.
        val lookupKey =
            FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)

        val tmp = File(filesDir, "$targetName.tmp")
        try {
            assets.open(lookupKey).use { input ->
                tmp.outputStream().use { output ->
                    val buffer = ByteArray(1 shl 20) // 1 MiB chunks
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            }
            // Atomic-ish swap so a killed process can't leave a truncated
            // model file that later looks "installed".
            if (!tmp.renameTo(target)) {
                throw IllegalStateException("Could not move model file into place")
            }
        } finally {
            if (tmp.exists() && !target.exists()) tmp.delete()
        }
        return target
    }
}
