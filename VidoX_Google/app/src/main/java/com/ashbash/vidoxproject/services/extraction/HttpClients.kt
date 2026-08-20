package com.ashbash.vidoxproject.services.extraction

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object HttpClients {
    const val DESKTOP_UA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    const val IPHONE_UA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.7 Mobile/15E148 Safari/604.1"
    const val YOUTUBE_VR_UA =
        "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
    const val YOUTUBE_IOS_UA =
        "com.google.ios.youtube/20.50.3 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)"

    val default: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    val fast: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(6, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    /** SnapSave / similar third-party resolvers that need a bit more than [fast]. */
    val medium: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    fun get(
        url: String,
        client: OkHttpClient = default,
        userAgent: String = DESKTOP_UA,
        headers: Map<String, String> = emptyMap()
    ): Response {
        val builder = Request.Builder()
            .url(url)
            .header("User-Agent", userAgent)
            .get()
        headers.forEach { (k, v) -> builder.header(k, v) }
        return client.newCall(builder.build()).execute()
    }

    fun postForm(
        url: String,
        form: Map<String, String>,
        client: OkHttpClient = default,
        userAgent: String = DESKTOP_UA,
        headers: Map<String, String> = emptyMap()
    ): Response {
        val body = okhttp3.FormBody.Builder().apply {
            form.forEach { (k, v) -> add(k, v) }
        }.build()
        val builder = Request.Builder()
            .url(url)
            .header("User-Agent", userAgent)
            .post(body)
        headers.forEach { (k, v) -> builder.header(k, v) }
        return client.newCall(builder.build()).execute()
    }
}

fun Response.bodyString(): String? = body?.string()

fun Response.jsonOrNull(): JSONObject? {
    val text = bodyString() ?: return null
    return try {
        JSONObject(text)
    } catch (_: Exception) {
        null
    }
}
