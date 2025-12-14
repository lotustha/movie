package com.lynoon.movie

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

class MainActivity: FlutterActivity() {
    // Define the channel name. It must match the one in your Flutter code.
    private val CHANNEL = "com.lynoon.movie/tv_channel"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Set up the MethodChannel.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            // This method is invoked on the main thread.
                call, result ->
            if (call.method == "updateTrendingMovies") {
                // Check if arguments are provided and are of the expected type.
                val moviesJson = call.argument<String>("moviesJson")
                if (moviesJson != null) {
                    // --- NATIVE ANDROID TV LOGIC ---
                    // 1. Create a Data object to pass the JSON to our worker.
                    //    The key "TRENDING_MOVIES_JSON" must match the key the worker expects.
                    val workData = Data.Builder()
                        .putString("TRENDING_MOVIES_JSON", moviesJson)
                        .build()

                    // 2. Build a one-time work request for our UpdateTvChannelWorker.
                    val updateRequest = OneTimeWorkRequestBuilder<UpdateTvChannelWorker>()
                        .setInputData(workData)
                        .build()

                    // 3. Enqueue the work request to be executed by WorkManager.
                    WorkManager.getInstance(applicationContext).enqueue(updateRequest)

                    println("WorkManager enqueued to update TV channel with trending movies.")

                    // Signal that the method call was successful.
                    result.success(null)
                } else {
                    // Signal that there was an error with the arguments.
                    result.error("INVALID_ARGUMENT", "moviesJson argument is null or missing", null)
                }
            } else {
                // Signal that the method is not implemented on the native side.
                result.notImplemented()
            }
        }
    }
}
