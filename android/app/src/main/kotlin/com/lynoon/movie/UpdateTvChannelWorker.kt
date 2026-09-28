package com.lynoon.movie

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import androidx.tvprovider.media.tv.Channel
import androidx.tvprovider.media.tv.ChannelLogoUtils
import androidx.tvprovider.media.tv.PreviewProgram
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

// Data classes to match the Flutter Subject model's JSON structure
data class Cover(val url: String?)
data class Subject(
    val title: String?,
    val cover: Cover?,
    val subjectId: String?,
    val description: String? = null,
    val subjectType: Int? = null,
    val releaseDate: String? = null,
    val genre: String? = null,
)

/**
 * Fills the "Trending on NoonFlix" row on the Android TV home screen.
 *
 * The app passes the list it just loaded (TRENDING_MOVIES_JSON); when the
 * launcher asks for programs, or the periodic refresh fires, there is no
 * input and the worker fetches the list from the API itself, so the row stays
 * fresh without the app being opened. An empty or failed fetch leaves the row
 * as it is instead of wiping it.
 */
class UpdateTvChannelWorker(appContext: Context, workerParams: WorkerParameters) :
    Worker(appContext, workerParams) {

    override fun doWork(): Result {
        return try {
            val movies = inputData.getString(KEY_JSON)
                ?.let { parse(it) }
                ?: fetchTrending(applicationContext)
                ?: return Result.retry()
            if (movies.isEmpty()) {
                Log.w(TAG, "No trending titles; keeping the existing row.")
                return Result.success()
            }

            val channelId = createOrGetChannel() ?: return Result.failure()
            // Only the app's first channel can be made visible without asking the user.
            TvContractCompat.requestChannelBrowsable(applicationContext, channelId)
            deleteExistingPrograms(channelId)
            addPrograms(movies, channelId)
            Log.d(TAG, "Channel $channelId updated with ${movies.size} programs.")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Updating the TV channel failed", e)
            Result.retry()
        }
    }

    private fun parse(json: String): List<Subject> = parseSubjects(JSONArray(json))

    @SuppressLint("RestrictedApi")
    private fun createOrGetChannel(): Long? {
        val resolver = applicationContext.contentResolver
        // Third-party apps only see their own channels here. Keep ours; drop
        // unkeyed ones older builds left behind so only one row remains.
        var existing: Long? = null
        for ((id, key, _) in TvChannels.channels(applicationContext)) {
            if (key == CHANNEL_KEY && existing == null) existing = id
            else resolver.delete(TvContractCompat.buildChannelUri(id), null, null)
        }
        if (existing != null) return existing

        val channel = Channel.Builder()
            .setType(TvContractCompat.Channels.TYPE_PREVIEW)
            .setDisplayName("Trending on NoonFlix")
            .setDescription("The most popular movies and shows right now.")
            .setInternalProviderId(CHANNEL_KEY)
            .setAppLinkIntentUri(Uri.parse("$LINK_BASE/home"))
            .build()
        val channelUri = resolver.insert(TvContractCompat.Channels.CONTENT_URI, channel.toContentValues())
        val channelId = channelUri?.let { android.content.ContentUris.parseId(it) } ?: return null

        val logo = BitmapFactory.decodeResource(applicationContext.resources, R.drawable.ic_launcher_foreground)
        if (logo != null) ChannelLogoUtils.storeChannelLogo(applicationContext, channelId, logo)
        return channelId
    }

    /**
     * The TV provider refuses a `selection` from third-party apps
     * ("Selection not allowed"), so list the channel's programs and delete
     * each one by its own URI.
     */
    private fun deleteExistingPrograms(channelId: Long) {
        val resolver = applicationContext.contentResolver
        val ids = mutableListOf<Long>()
        resolver.query(
            TvContractCompat.buildPreviewProgramsUriForChannel(channelId),
            arrayOf(TvContractCompat.PreviewPrograms._ID), null, null, null
        )?.use { cursor ->
            while (cursor.moveToNext()) ids.add(cursor.getLong(0))
        }
        ids.forEach { resolver.delete(TvContractCompat.buildPreviewProgramUri(it), null, null) }
    }

    private fun addPrograms(movies: List<Subject>, channelId: Long) {
        val values = movies.mapIndexed { i, movie ->
            val builder = PreviewProgram.Builder()
                .setChannelId(channelId)
                .setTitle(movie.title)
                .setDescription(movie.description)
                .setPosterArtUri(movie.cover?.url?.let { Uri.parse(posterUrl(it)) })
                .setPosterArtAspectRatio(TvContractCompat.PreviewPrograms.ASPECT_RATIO_2_3)
                .setIntentUri(Uri.parse("$LINK_BASE/details/${movie.subjectId}"))
                .setInternalProviderId(movie.subjectId)
                .setWeight(movies.size - i)
                .setType(
                    if (movie.subjectType == 2) TvContractCompat.PreviewPrograms.TYPE_TV_SERIES
                    else TvContractCompat.PreviewPrograms.TYPE_MOVIE
                )
            movie.releaseDate?.takeIf { it.length >= 4 }?.let { builder.setReleaseDate(it.substring(0, 4)) }
            movie.genre?.takeIf { it.isNotBlank() }?.let { builder.setGenre(it) }
            builder.build().toContentValues()
        }.toTypedArray()
        applicationContext.contentResolver.bulkInsert(TvContractCompat.PreviewPrograms.CONTENT_URI, values)
    }

    companion object {
        const val TAG = "NoonFlixTv"
        const val KEY_JSON = "TRENDING_MOVIES_JSON"
        const val CHANNEL_KEY = "trending"
        const val LINK_BASE = "flutter-tv-app://com.lynoon.movie"
        private const val PREFS = "noonflix_tv"
        private const val DEFAULT_API = "https://api.mugenstream.fun"
        private const val DEFAULT_RANKING = "997144265920760504" // "Popular"

        /** Resized poster: launcher tiles are small, full-size covers are ~1 MB. */
        fun posterUrl(url: String) = if (url.contains("?")) url else "$url?x-oss-process=image/resize,w_400"

        // Parsed by hand: Gson reflection breaks under R8 in release builds.
        fun parseSubjects(array: JSONArray): List<Subject> = (0 until array.length()).mapNotNull { i ->
            val o = array.optJSONObject(i) ?: return@mapNotNull null
            val id = o.str("subjectId") ?: return@mapNotNull null
            Subject(
                title = o.str("title"),
                cover = Cover(o.optJSONObject("cover")?.str("url")),
                subjectId = id,
                description = o.str("description"),
                subjectType = if (o.has("subjectType") && !o.isNull("subjectType")) o.optInt("subjectType") else null,
                releaseDate = o.str("releaseDate"),
                genre = o.str("genre"),
            )
        }

        /** A string field, or null when missing, JSON null or blank. */
        fun JSONObject.str(key: String): String? =
            if (isNull(key)) null else optString(key).takeIf { it.isNotBlank() }

        /** Remembers where the app's API lives so background refreshes use the same one. */
        fun saveSource(context: Context, apiBase: String?, rankingId: String?) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
                if (!apiBase.isNullOrBlank()) putString("api", apiBase)
                if (!rankingId.isNullOrBlank()) putString("ranking", rankingId)
                apply()
            }
        }

        fun fetchTrending(context: Context): List<Subject>? {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val api = prefs.getString("api", DEFAULT_API)
            val ranking = prefs.getString("ranking", DEFAULT_RANKING)
            val conn = URL("$api/movie-tv/moviebox/ranking/$ranking?page=1&perPage=20")
                .openConnection() as HttpURLConnection
            return try {
                conn.connectTimeout = 15000
                conn.readTimeout = 30000
                if (conn.responseCode != 200) return null
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                parseSubjects(JSONObject(body).optJSONArray("subjectList") ?: return null)
            } catch (e: Exception) {
                Log.w(TAG, "Fetching trending failed: $e")
                null
            } finally {
                conn.disconnect()
            }
        }
    }
}
