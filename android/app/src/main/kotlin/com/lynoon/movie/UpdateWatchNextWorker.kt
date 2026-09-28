package com.lynoon.movie

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray

data class WatchNextItem(
    val subjectId: String?,
    val title: String?,
    val cover: String?,
    val subjectType: Int?,
    val season: Int?,
    val episode: Int?,
    val positionSec: Long?,
    val durationSec: Long?,
    val updatedAt: Long?,
)

/**
 * Mirrors the app's Continue Watching list into the launcher's "Play Next"
 * row. Selecting an entry opens the title and resumes where it stopped.
 */
class UpdateWatchNextWorker(appContext: Context, workerParams: WorkerParameters) :
    Worker(appContext, workerParams) {

    override fun doWork(): Result {
        val json = inputData.getString(KEY_JSON) ?: return Result.failure()
        return try {
            val items = parse(JSONArray(json))
            val resolver = applicationContext.contentResolver

            // Existing rows of ours, keyed by subject id.
            val existing = mutableMapOf<String, Long>()
            resolver.query(
                TvContractCompat.WatchNextPrograms.CONTENT_URI,
                arrayOf(
                    TvContractCompat.WatchNextPrograms._ID,
                    TvContractCompat.WatchNextPrograms.COLUMN_INTERNAL_PROVIDER_ID
                ),
                null, null, null
            )?.use { c ->
                while (c.moveToNext()) {
                    val key = c.getString(1)
                    if (key != null) existing[key] = c.getLong(0) else {
                        resolver.delete(TvContractCompat.buildWatchNextProgramUri(c.getLong(0)), null, null)
                    }
                }
            }

            val keep = items.mapNotNull { it.subjectId }.toSet()
            existing.filterKeys { it !in keep }.values.forEach {
                resolver.delete(TvContractCompat.buildWatchNextProgramUri(it), null, null)
            }

            val now = System.currentTimeMillis()
            items.forEachIndexed { i, item ->
                val builder = WatchNextProgram.Builder()
                    .setWatchNextType(TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE)
                    .setLastEngagementTimeUtcMillis(item.updatedAt ?: (now - i * 1000L))
                    .setTitle(item.title)
                    .setPosterArtUri(item.cover?.let { Uri.parse(UpdateTvChannelWorker.posterUrl(it)) })
                    .setPosterArtAspectRatio(TvContractCompat.WatchNextPrograms.ASPECT_RATIO_2_3)
                    .setIntentUri(Uri.parse("${UpdateTvChannelWorker.LINK_BASE}/resume/${item.subjectId}"))
                    .setInternalProviderId(item.subjectId)
                    .setType(
                        if (item.subjectType == 2) TvContractCompat.WatchNextPrograms.TYPE_TV_EPISODE
                        else TvContractCompat.WatchNextPrograms.TYPE_MOVIE
                    )
                val pos = item.positionSec ?: 0
                val dur = item.durationSec ?: 0
                if (dur > 0) {
                    builder.setDurationMillis((dur * 1000).toInt())
                    builder.setLastPlaybackPositionMillis((pos * 1000).toInt())
                }
                if (item.subjectType == 2 && item.season != null && item.episode != null) {
                    builder.setSeasonNumber(item.season).setEpisodeNumber(item.episode)
                }
                val values = builder.build().toContentValues()
                val id = existing[item.subjectId]
                if (id != null) {
                    resolver.update(TvContractCompat.buildWatchNextProgramUri(id), values, null, null)
                } else {
                    resolver.insert(TvContractCompat.WatchNextPrograms.CONTENT_URI, values)
                }
            }
            Log.d(UpdateTvChannelWorker.TAG, "Play Next updated with ${items.size} titles.")
            Result.success()
        } catch (e: Exception) {
            Log.e(UpdateTvChannelWorker.TAG, "Updating Play Next failed", e)
            Result.failure()
        }
    }

    // Parsed by hand: Gson reflection breaks under R8 in release builds.
    private fun parse(array: JSONArray): List<WatchNextItem> = (0 until array.length()).mapNotNull { i ->
        val o = array.optJSONObject(i) ?: return@mapNotNull null
        fun str(k: String) = if (o.isNull(k)) null else o.optString(k).takeIf { it.isNotBlank() }
        fun num(k: String) = if (o.isNull(k)) null else o.optLong(k)
        WatchNextItem(
            subjectId = str("subjectId") ?: return@mapNotNull null,
            title = str("title"),
            cover = str("cover"),
            subjectType = num("subjectType")?.toInt(),
            season = num("season")?.toInt(),
            episode = num("episode")?.toInt(),
            positionSec = num("positionSec"),
            durationSec = num("durationSec"),
            updatedAt = num("updatedAt"),
        )
    }

    companion object {
        const val KEY_JSON = "WATCH_NEXT_JSON"
    }
}
