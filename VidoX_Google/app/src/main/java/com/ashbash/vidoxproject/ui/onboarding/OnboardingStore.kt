package com.ashbash.vidoxproject.ui.onboarding

import android.content.Context

object OnboardingStore {
    private const val PREFS = "vidox_onboarding"
    private const val KEY_COMPLETED = "completed"
    private const val KEY_LAST_SEEN_VERSION = "whats_new_last_seen"

    fun isCompleted(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_COMPLETED, false)

    fun setCompleted(context: Context, completed: Boolean = true) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_COMPLETED, completed)
            .apply()
    }

    fun lastSeenVersion(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_LAST_SEEN_VERSION, "")
            .orEmpty()

    fun markCurrentVersionSeen(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LAST_SEEN_VERSION, WhatsNewNotes.currentVersion)
            .apply()
    }
}
