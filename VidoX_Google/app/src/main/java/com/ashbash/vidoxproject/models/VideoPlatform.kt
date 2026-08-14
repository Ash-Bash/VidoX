package com.ashbash.vidoxproject.models

import androidx.compose.ui.graphics.Color

/**
 * Video hosts VidoX can recognize from a pasted URL (pages or direct files).
 * Host list matches the Apple [VideoPlatform] enum for parity.
 */
enum class VideoPlatform(val rawValue: String) {
    YOUTUBE("youtube"),
    TWITTER("twitter"),
    INSTAGRAM("instagram"),
    FACEBOOK("facebook"),
    TIKTOK("tiktok"),
    VIMEO("vimeo"),
    DAILYMOTION("dailymotion"),
    REDDIT("reddit"),
    TWITCH("twitch"),
    STREAMABLE("streamable"),
    RUMBLE("rumble"),
    WEB("web"),
    UNKNOWN("unknown");

    val displayName: String
        get() = when (this) {
            YOUTUBE -> "YouTube"
            TWITTER -> "X"
            INSTAGRAM -> "Instagram"
            FACEBOOK -> "Facebook"
            TIKTOK -> "TikTok"
            VIMEO -> "Vimeo"
            DAILYMOTION -> "Dailymotion"
            REDDIT -> "Reddit"
            TWITCH -> "Twitch"
            STREAMABLE -> "Streamable"
            RUMBLE -> "Rumble"
            WEB -> "Web"
            UNKNOWN -> "Direct"
        }

    val accentColor: Color
        get() = when (this) {
            YOUTUBE -> Color(1f, 0f, 0f)
            TWITTER -> Color(0.1f, 0.1f, 0.1f)
            INSTAGRAM -> Color(0.88f, 0.19f, 0.42f)
            FACEBOOK -> Color(0.09f, 0.47f, 0.95f)
            TIKTOK -> Color(0f, 0.96f, 0.88f)
            VIMEO -> Color(0.13f, 0.71f, 0.98f)
            DAILYMOTION -> Color(0f, 0.4f, 0.85f)
            REDDIT -> Color(1f, 0.27f, 0f)
            TWITCH -> Color(0.57f, 0.27f, 1f)
            STREAMABLE -> Color(0.05f, 0.65f, 0.91f)
            RUMBLE -> Color(0.42f, 0.75f, 0.12f)
            WEB -> Color(0.2f, 0.45f, 0.9f)
            UNKNOWN -> Color(0.5f, 0.5f, 0.5f)
        }

    val isPageHost: Boolean
        get() = this != UNKNOWN

    companion object {
        fun fromRaw(raw: String): VideoPlatform =
            entries.firstOrNull { it.rawValue == raw } ?: UNKNOWN

        fun detect(urlString: String): VideoPlatform {
            val lower = urlString.lowercase()
            val host = try {
                java.net.URI(lower).host?.lowercase().orEmpty()
            } catch (_: Exception) {
                ""
            }
            val hosts: List<Pair<VideoPlatform, List<String>>> = listOf(
                YOUTUBE to listOf("youtube.com", "youtu.be", "youtube-nocookie.com", "m.youtube.com"),
                // Match host labels only — bare "t.co" must not match inside "reddit.com".
                TWITTER to listOf("twitter.com", "x.com", "t.co", "mobile.twitter.com"),
                INSTAGRAM to listOf("instagram.com", "instagr.am", "kkinstagram.com"),
                FACEBOOK to listOf(
                    "facebook.com", "fb.watch", "fb.com", "fb.me",
                    "m.facebook.com", "web.facebook.com", "mbasic.facebook.com"
                ),
                TIKTOK to listOf("tiktok.com", "vm.tiktok.com", "vt.tiktok.com"),
                VIMEO to listOf("vimeo.com", "player.vimeo.com"),
                DAILYMOTION to listOf("dailymotion.com", "dai.ly"),
                REDDIT to listOf("reddit.com", "redd.it", "v.redd.it", "old.reddit.com"),
                TWITCH to listOf("twitch.tv", "clips.twitch.tv", "m.twitch.tv"),
                STREAMABLE to listOf("streamable.com"),
                RUMBLE to listOf("rumble.com", "rumble.cloud")
            )
            if (host.isNotEmpty()) {
                for ((platform, patterns) in hosts) {
                    if (patterns.any { pattern -> host == pattern || host.endsWith(".$pattern") }) {
                        return platform
                    }
                }
            }
            // Fallback for non-parseable paste strings.
            for ((platform, patterns) in hosts) {
                if (patterns.any { pattern ->
                        Regex("""(^|[/.])${Regex.escape(pattern)}([/?#]|$)""")
                            .containsMatchIn(lower)
                    }
                ) {
                    return platform
                }
            }
            return UNKNOWN
        }
    }
}
