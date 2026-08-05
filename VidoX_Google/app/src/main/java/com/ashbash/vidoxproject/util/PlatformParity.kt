package com.ashbash.vidoxproject.util

import com.ashbash.vidoxproject.models.VideoPlatform

/**
 * Acceptance checklist for social platform parity with Apple.
 * Used by unit tests and Settings documentation — every host family must have
 * a native and/or yt-dlp path in ExtractionRouter / ExperimentalSocialExtractor.
 */
object PlatformParity {
    val requiredHosts: List<VideoPlatform> = listOf(
        VideoPlatform.YOUTUBE,
        VideoPlatform.TWITTER,
        VideoPlatform.INSTAGRAM,
        VideoPlatform.FACEBOOK,
        VideoPlatform.TIKTOK,
        VideoPlatform.VIMEO,
        VideoPlatform.DAILYMOTION,
        VideoPlatform.REDDIT,
        VideoPlatform.TWITCH,
        VideoPlatform.STREAMABLE,
        VideoPlatform.RUMBLE,
        VideoPlatform.WEB,
        VideoPlatform.UNKNOWN // direct files
    )

    /** Hosts that prefer native page extractors before yt-dlp (Apple Mac strategy). */
    val preferNative: Set<VideoPlatform> = setOf(
        VideoPlatform.FACEBOOK,
        VideoPlatform.INSTAGRAM,
        VideoPlatform.TWITTER,
        VideoPlatform.TIKTOK,
        VideoPlatform.REDDIT,
        VideoPlatform.STREAMABLE
    )

    fun detectSample(url: String): VideoPlatform = VideoPlatform.detect(url)
}
