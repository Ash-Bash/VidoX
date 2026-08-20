package com.ashbash.vidoxproject.services.download

import com.ashbash.vidoxproject.services.extraction.HttpClients
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import okhttp3.Request
import java.io.File
import java.io.RandomAccessFile
import java.net.URL

/** Streams a remote file to disk with byte-level progress via OkHttp. */
class OkHttpVideoDownloader : VideoDownloading {
    override fun download(from: URL, to: File): Flow<DownloadProgress> = flow {
        val request = Request.Builder()
            .url(from)
            .apply { applyRefererHeaders(from) }
            .build()

        HttpClients.default.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw DownloadError.HttpStatus(response.code)
            val body = response.body ?: throw DownloadError.InvalidResponse
            val total = body.contentLength().takeIf { it >= 0 }
            to.parentFile?.mkdirs()
            var received = 0L
            body.byteStream().use { input ->
                RandomAccessFile(to, "rw").use { raf ->
                    raf.setLength(0)
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        raf.write(buffer, 0, read)
                        received += read
                        emit(DownloadProgress(received, total))
                    }
                }
            }
            if (received == 0L) throw DownloadError.WriteFailed("Empty download.")
            emit(DownloadProgress(received, total ?: received))
        }
    }.flowOn(Dispatchers.IO)

    private fun Request.Builder.applyRefererHeaders(remoteURL: URL): Request.Builder {
        val host = remoteURL.host?.lowercase().orEmpty()
        val path = remoteURL.path.lowercase()
        val absolute = remoteURL.toString().lowercase()
        when {
            host.contains("googlevideo.com") || host.contains("youtube.com") -> {
                val isHls = path.contains(".m3u8") || absolute.contains("manifest/hls")
                header("User-Agent", if (isHls) HttpClients.YOUTUBE_IOS_UA else HttpClients.YOUTUBE_VR_UA)
                header("Referer", "https://www.youtube.com/")
            }
            else -> {
                header("User-Agent", HttpClients.IPHONE_UA)
            }
        }
        when {
            host.contains("cdninstagram.com") || host.contains("fbcdn.net") || host.contains("scontent") -> {
                header("Referer", "https://www.instagram.com/")
                header("Origin", "https://www.instagram.com")
            }
            host.contains("ssscdn.io") || host.contains("rapidcdn.app") || host.contains("getmyfb") ||
                host.contains("facebook.com") -> {
                header("Referer", "https://www.facebook.com/")
                header("Origin", "https://www.facebook.com")
            }
            host.contains("tiktokcdn") || host.contains("tiktok.com") || host.contains("byteoversea") ||
                host.contains("musical.ly") || host.contains("tokcdn") -> {
                header("Referer", "https://www.tiktok.com/")
                header("Origin", "https://www.tiktok.com")
            }
            host.contains("twimg.com") || host.contains("video.twimg.com") || host.contains("x.com") -> {
                header("Referer", "https://x.com/")
                header("Origin", "https://x.com")
            }
            host.contains("vimeocdn.com") || host.contains("vimeo.com") -> {
                header("Referer", "https://vimeo.com/")
                header("Origin", "https://vimeo.com")
            }
            host.contains("dailymotion.com") || host.contains("dmcdn.net") || host.contains("dmxleo") -> {
                header("Referer", "https://www.dailymotion.com/")
            }
            host.contains("redd.it") || host.contains("reddit.com") || host.contains("redditmedia") -> {
                header("Referer", "https://www.reddit.com/")
            }
            host.contains("ttvnw.net") || host.contains("twitchcdn") || host.contains("twitch.tv") -> {
                header("Referer", "https://www.twitch.tv/")
            }
            host.contains("streamable.com") -> header("Referer", "https://streamable.com/")
            host.contains("rumble.com") || host.contains("rmbl.ws") -> {
                header("Referer", "https://rumble.com/")
            }
        }
        return this
    }
}
