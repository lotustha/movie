package com.lynoon.movie

import android.content.Intent
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun onResume() {
        super.onResume()
        TvChannels.promptIfHidden(this)
    }

    // Must match the channel name in HomeScreenController.
    private val CHANNEL = "com.lynoon.movie/tv_channel"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        TvChannels.schedulePeriodic(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // The "Trending on NoonFlix" row on the TV home screen.
                "updateTrendingMovies" -> {
                    val moviesJson = call.argument<String>("moviesJson")
                    if (moviesJson == null) {
                        result.error("INVALID_ARGUMENT", "moviesJson argument is null or missing", null)
                    } else {
                        UpdateTvChannelWorker.saveSource(
                            applicationContext,
                            call.argument<String>("apiBase"),
                            call.argument<String>("rankingId"),
                        )
                        TvChannels.refreshNow(applicationContext, moviesJson)
                        result.success(null)
                    }
                }
                // Continue Watching → the launcher's "Play Next" row.
                "updateWatchNext" -> {
                    val json = call.argument<String>("itemsJson")
                    if (json == null) {
                        result.error("INVALID_ARGUMENT", "itemsJson argument is null or missing", null)
                    } else {
                        TvChannels.updateWatchNext(applicationContext, json)
                        result.success(null)
                    }
                }
                // Android TV (leanback): the app asks before letting anyone watch.
                "isTv" -> result.success(TvChannels.isTv(applicationContext))
                // In-app update: open the system installer on a downloaded APK.
                // Android itself asks to allow installs from this app the first time.
                "installApk" -> {
                    val path = call.argument<String>("path")
                    val file = path?.let { File(it) }
                    if (file == null || !file.exists()) {
                        result.error("INVALID_ARGUMENT", "No update file at $path", null)
                    } else {
                        try {
                            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                            startActivity(
                                Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
