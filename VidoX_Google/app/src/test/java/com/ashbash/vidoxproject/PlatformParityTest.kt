package com.ashbash.vidoxproject

import com.ashbash.vidoxproject.models.VideoPlatform
import com.ashbash.vidoxproject.services.extraction.DirectMediaExtractor
import com.ashbash.vidoxproject.util.PlatformParity
import com.ashbash.vidoxproject.util.URLNormalizer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URL

/** Verifies host detection / routing coverage for every Apple-parity platform. */
class PlatformParityTest {

    @Test
    fun requiredHostsAreDetected() {
        val samples = mapOf(
            VideoPlatform.YOUTUBE to "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            VideoPlatform.TWITTER to "https://x.com/user/status/1234567890",
            VideoPlatform.INSTAGRAM to "https://www.instagram.com/reel/AbCdEfGhIjK/",
            VideoPlatform.FACEBOOK to "https://www.facebook.com/watch/?v=1234567890",
            VideoPlatform.TIKTOK to "https://www.tiktok.com/@user/video/1234567890",
            VideoPlatform.VIMEO to "https://vimeo.com/123456789",
            VideoPlatform.DAILYMOTION to "https://www.dailymotion.com/video/x123abc",
            VideoPlatform.REDDIT to "https://www.reddit.com/r/videos/comments/abc123/title/",
            VideoPlatform.TWITCH to "https://clips.twitch.tv/SomeClipSlug",
            VideoPlatform.STREAMABLE to "https://streamable.com/abcd12",
            VideoPlatform.RUMBLE to "https://rumble.com/v123456-title.html"
        )
        samples.forEach { (expected, url) ->
            assertEquals("detect failed for $url", expected, VideoPlatform.detect(url))
        }
        assertTrue(PlatformParity.requiredHosts.containsAll(samples.keys))
    }

    @Test
    fun urlNormalizerAcceptsHttpsAndStripsTracking() {
        val url = URLNormalizer.url("https://www.youtube.com/watch?v=abc123&utm_source=share")
        assertNotNull(url)
        assertTrue(url!!.toString().contains("v=abc123"))
        assertTrue(!url.toString().contains("utm_source"))
    }

    @Test
    fun facebookVideoIdParsed() {
        val id = URLNormalizer.facebookVideoID(
            URL("https://www.facebook.com/watch/?v=9876543210")
        )
        assertEquals("9876543210", id)
    }

    @Test
    fun directMediaLooksLikeFile() {
        assertTrue(
            DirectMediaExtractor.looksLikeDirectMediaURL(
                URL("https://cdn.example.com/clip.mp4")
            )
        )
    }

    @Test
    fun preferNativeMatchesAppleStrategy() {
        assertTrue(PlatformParity.preferNative.contains(VideoPlatform.FACEBOOK))
        assertTrue(PlatformParity.preferNative.contains(VideoPlatform.TIKTOK))
        assertTrue(!PlatformParity.preferNative.contains(VideoPlatform.YOUTUBE))
    }
}
