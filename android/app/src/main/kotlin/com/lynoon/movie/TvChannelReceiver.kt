package com.lynoon.movie

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * The launcher sends INITIALIZE_PROGRAMS right after install (and on boot
 * some launchers re-send it): create the channel then, so the row appears
 * before the app is ever opened.
 */
class TvChannelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        TvChannels.refreshNow(context)
        TvChannels.schedulePeriodic(context)
    }
}
