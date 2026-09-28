package com.lynoon.movie

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/** Scheduling for the launcher rows; a no-op on phones. */
object TvChannels {
    private const val UNIQUE_NOW = "tv_channel_now"
    private const val UNIQUE_PERIODIC = "tv_channel_periodic"
    private const val UNIQUE_WATCH_NEXT = "tv_watch_next"

    fun isTv(context: Context): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)

    private val online = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    /** Refresh the trending row now; with [json], use that list instead of fetching. */
    fun refreshNow(context: Context, json: String? = null) {
        if (!isTv(context)) return
        val request = OneTimeWorkRequestBuilder<UpdateTvChannelWorker>()
            .setConstraints(online)
            .apply { if (json != null) setInputData(Data.Builder().putString(UpdateTvChannelWorker.KEY_JSON, json).build()) }
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(UNIQUE_NOW, ExistingWorkPolicy.REPLACE, request)
    }

    /** Keeps the row fresh while the app is closed. */
    fun schedulePeriodic(context: Context) {
        if (!isTv(context)) return
        val request = PeriodicWorkRequestBuilder<UpdateTvChannelWorker>(6, TimeUnit.HOURS)
            .setConstraints(online)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(UNIQUE_PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    /**
     * Our channels as (id, internal key, browsable). Old builds could leave
     * extra channels behind; those are deleted so only one row remains.
     */
    fun channels(context: Context): List<Triple<Long, String?, Boolean>> {
        val out = mutableListOf<Triple<Long, String?, Boolean>>()
        context.contentResolver.query(
            TvContractCompat.Channels.CONTENT_URI,
            arrayOf(
                TvContractCompat.Channels._ID,
                TvContractCompat.Channels.COLUMN_INTERNAL_PROVIDER_ID,
                TvContractCompat.Channels.COLUMN_BROWSABLE
            ),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) out.add(Triple(c.getLong(0), c.getString(1), c.getInt(2) == 1))
        }
        return out
    }

    /**
     * The launcher hides app channels until the user (or the one-time
     * default-channel grant) makes them browsable. When ours is hidden, ask
     * once per app version with the system "Add to Home screen" dialog.
     */
    fun promptIfHidden(activity: Activity) {
        if (!isTv(activity)) return
        Thread {
            try {
                val ours = channels(activity)
                Log.d(UpdateTvChannelWorker.TAG, "Channels: $ours")
                val channel = ours.firstOrNull { it.second == UpdateTvChannelWorker.CHANNEL_KEY } ?: return@Thread
                if (channel.third) return@Thread
                val prefs = activity.getSharedPreferences("noonflix_tv", Context.MODE_PRIVATE)
                val version = activity.packageManager.getPackageInfo(activity.packageName, 0).lastUpdateTime
                if (prefs.getLong("prompted_for", 0) == version) return@Thread
                prefs.edit().putLong("prompted_for", version).apply()
                activity.runOnUiThread {
                    try {
                        activity.startActivityForResult(
                            Intent(TvContractCompat.ACTION_REQUEST_CHANNEL_BROWSABLE)
                                .putExtra(TvContractCompat.EXTRA_CHANNEL_ID, channel.first),
                            REQUEST_BROWSABLE
                        )
                    } catch (e: Exception) {
                        Log.w(UpdateTvChannelWorker.TAG, "Launcher can't prompt for the channel: $e")
                    }
                }
            } catch (e: Exception) {
                Log.w(UpdateTvChannelWorker.TAG, "Channel check failed: $e")
            }
        }.start()
    }

    const val REQUEST_BROWSABLE = 4107

    fun updateWatchNext(context: Context, json: String) {
        if (!isTv(context)) return
        val request = OneTimeWorkRequestBuilder<UpdateWatchNextWorker>()
            .setInputData(Data.Builder().putString(UpdateWatchNextWorker.KEY_JSON, json).build())
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(UNIQUE_WATCH_NEXT, ExistingWorkPolicy.REPLACE, request)
    }
}
