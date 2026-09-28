package com.lynoon.movie

import androidx.annotation.NonNull
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
                else -> result.notImplemented()
            }
        }
    }
}
