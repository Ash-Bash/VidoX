package com.ashbash.vidoxproject.util

/**
 * Compile-time switches for sideload behaviour.
 *
 * Sideload builds keep [experimentalSocialDownloads] true so social hosts download for real.
 * Set false only if you want preview-only page URLs.
 */
object FeatureFlags {
    const val experimentalSocialDownloads: Boolean = true
}
