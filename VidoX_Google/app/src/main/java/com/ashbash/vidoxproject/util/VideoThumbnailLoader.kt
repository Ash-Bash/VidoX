package com.ashbash.vidoxproject.util

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.File
import java.io.FileOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Extracts a still frame from a local video (same idea as Apple’s AVAssetImageGenerator)
 * and caches a JPEG so list/grid scrolling stays cheap.
 */
object VideoThumbnailLoader {
    private val locks = mutableMapOf<String, Mutex>()
    private val locksGuard = Any()

    private fun mutexFor(key: String): Mutex = synchronized(locksGuard) {
        locks.getOrPut(key) { Mutex() }
    }

    suspend fun cachedOrGenerate(videoFile: File, cacheDir: File): File? =
        withContext(Dispatchers.IO) {
            if (!videoFile.exists()) return@withContext null
            cacheDir.mkdirs()
            val cacheFile = File(cacheDir, "${videoFile.nameWithoutExtension}.thumb.jpg")
            if (cacheFile.exists() && cacheFile.length() > 0L) return@withContext cacheFile

            mutexFor(videoFile.absolutePath).withLock {
                if (cacheFile.exists() && cacheFile.length() > 0L) return@withLock cacheFile
                val frame = extractFrame(videoFile) ?: return@withLock null
                try {
                    FileOutputStream(cacheFile).use { out ->
                        frame.compress(Bitmap.CompressFormat.JPEG, 85, out)
                    }
                    cacheFile
                } catch (_: Exception) {
                    cacheFile.delete()
                    null
                } finally {
                    frame.recycle()
                }
            }
        }

    fun cacheFileFor(videoFile: File, cacheDir: File): File =
        File(cacheDir, "${videoFile.nameWithoutExtension}.thumb.jpg")

    private fun extractFrame(videoFile: File): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoFile.absolutePath)
            // Prefer a non-black frame — some social downloads start on a black slate.
            val candidates = longArrayOf(1_000_000L, 2_000_000L, 500_000L, 0L, 3_000_000L)
            var best: Bitmap? = null
            for (timeUs in candidates) {
                val frame = frameAt(retriever, timeUs) ?: continue
                if (!isMostlyBlack(frame)) {
                    best?.recycle()
                    return frame
                }
                if (best == null) {
                    best = frame
                } else {
                    frame.recycle()
                }
            }
            best
        } catch (_: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // ignore
            }
        }
    }

    /** True when the frame is nearly solid black (common Instagram/TikTok intro slate). */
    private fun isMostlyBlack(bitmap: Bitmap): Boolean {
        val w = bitmap.width.coerceAtLeast(1)
        val h = bitmap.height.coerceAtLeast(1)
        val stepX = (w / 8).coerceAtLeast(1)
        val stepY = (h / 8).coerceAtLeast(1)
        var dark = 0
        var total = 0
        var y = 0
        while (y < h) {
            var x = 0
            while (x < w) {
                val c = bitmap.getPixel(x, y)
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val b = c and 0xFF
                if (r + g + b < 36) dark++
                total++
                x += stepX
            }
            y += stepY
        }
        return total > 0 && dark.toFloat() / total.toFloat() > 0.92f
    }

    private fun frameAt(retriever: MediaMetadataRetriever, timeUs: Long): Bitmap? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            retriever.getScaledFrameAtTime(
                timeUs,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                480,
                480
            )
        } else {
            retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?.let { scaleDown(it, 480) }
        }
    }

    private fun scaleDown(source: Bitmap, maxSide: Int): Bitmap {
        val longest = maxOf(source.width, source.height)
        if (longest <= maxSide) return source
        val scale = maxSide.toFloat() / longest.toFloat()
        val w = (source.width * scale).toInt().coerceAtLeast(1)
        val h = (source.height * scale).toInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(source, w, h, true)
        if (scaled !== source) source.recycle()
        return scaled
    }
}
