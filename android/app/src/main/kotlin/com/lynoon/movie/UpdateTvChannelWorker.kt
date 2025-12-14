package com.lynoon.movie

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.tvprovider.media.tv.Channel
import androidx.tvprovider.media.tv.ChannelLogoUtils
import androidx.tvprovider.media.tv.PreviewProgram
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.lynoon.movie.R

// Data classes to match the Flutter Subject model's JSON structure
data class Cover(val url: String?)
data class Subject(val title: String?, val cover: Cover?, val subjectId: String?)

class UpdateTvChannelWorker(appContext: Context, workerParams: WorkerParameters) :
    Worker(appContext, workerParams) {

    override fun doWork(): Result {
        val moviesJson = inputData.getString("TRENDING_MOVIES_JSON")
        if (moviesJson.isNullOrEmpty()) {
            return Result.failure()
        }

        // Ensure the "Trending" channel exists (or create it)
        val channelId = createOrGetChannel() ?: return Result.failure()

        // ✅ Ask Google TV to make the channel visible to the user
        TvContractCompat.requestChannelBrowsable(applicationContext, channelId)

        // Update the programs on the channel
        deleteExistingPrograms(channelId) // Pass channelId to delete specifically
        addTrendingMovies(moviesJson, channelId)

        return Result.success()
    }

    private fun createOrGetChannel(): Long? {
        // Check if our "Trending" channel already exists.
        val projection = arrayOf(TvContractCompat.Channels._ID)
        // A more robust query would be to filter by a unique internal ID if you planned
        // to have multiple channels, but for a single channel this is fine.
        applicationContext.contentResolver.query(
            TvContractCompat.Channels.CONTENT_URI, projection, null, null, null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                // Channel already exists, return its ID.
                return cursor.getLong(0)
            }
        }

        // Channel doesn't exist, so create it.
        val builder = Channel.Builder()
            .setType(TvContractCompat.Channels.TYPE_PREVIEW)
            .setDisplayName("Trending Movies")
            .setAppLinkIntentUri(Uri.parse("flutter-tv-app://com.lynoon.movie/home"))
            // Optional: Add a description
            .setDescription("The latest and most popular movies right now.")

        val channel = builder.build()
        val channelUri = applicationContext.contentResolver.insert(
            TvContractCompat.Channels.CONTENT_URI, channel.toContentValues()
        )

        val channelId = channelUri?.lastPathSegment?.toLongOrNull()
        if (channelId != null) {
            // Store the channel logo
            val logo = BitmapFactory.decodeResource(applicationContext.resources, R.mipmap.ic_launcher)
            ChannelLogoUtils.storeChannelLogo(applicationContext, channelId, logo)
        }
        return channelId
    }

    /**
     * Deletes existing programs ONLY for the specified channelId.
     */
    private fun deleteExistingPrograms(channelId: Long) {
        val selection = "${TvContractCompat.PreviewPrograms.COLUMN_CHANNEL_ID} = ?"
        val selectionArgs = arrayOf(channelId.toString())
        applicationContext.contentResolver.delete(
            TvContractCompat.PreviewPrograms.CONTENT_URI, selection, selectionArgs
        )
    }

    /**
     * Parses the movie JSON and adds the movies as programs to the channel.
     * Uses bulkInsert for better performance.
     */
    private fun addTrendingMovies(moviesJson: String, channelId: Long) {
        val gson = Gson()
        val subjectListType = object : TypeToken<List<Subject>>() {}.type
        val trendingMovies: List<Subject> = gson.fromJson(moviesJson, subjectListType)

        val programs = trendingMovies.map { movie ->
            val posterUri = movie.cover?.url?.let { Uri.parse(it) }
            val intentUri = Uri.parse("flutter-tv-app://com.lynoon.movie/details/${movie.subjectId}")

            PreviewProgram.Builder()
                .setChannelId(channelId) // ✅ assign to our channel
                .setTitle(movie.title)
                .setPosterArtUri(posterUri)
                .setIntentUri(intentUri)
                .setInternalProviderId(movie.subjectId)
                // Optional: Define program type
                .setType(TvContractCompat.PreviewPrograms.TYPE_MOVIE)
                .build()
        }

        if (programs.isNotEmpty()) {
            val contentValues = programs.map { it.toContentValues() }.toTypedArray()
            applicationContext.contentResolver.bulkInsert(
                TvContractCompat.PreviewPrograms.CONTENT_URI, contentValues
            )
        }
    }
}
