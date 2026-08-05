package com.ashbash.vidoxproject

import android.app.Application
import com.ashbash.vidoxproject.data.VidoXDatabase
import com.ashbash.vidoxproject.data.VideoRepository
import com.ashbash.vidoxproject.services.extraction.YtDlpTool
import com.ashbash.vidoxproject.util.FileStorage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class VidoXApp : Application() {
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    lateinit var fileStorage: FileStorage
        private set
    lateinit var repository: VideoRepository
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        fileStorage = FileStorage(this)
        val db = VidoXDatabase.get(this)
        repository = VideoRepository(db.downloadedVideoDao(), fileStorage)

        // Warm yt-dlp/ffmpeg in the background for sideload downloads.
        appScope.launch {
            runCatching { YtDlpTool.ensureInitialized(this@VidoXApp) }
        }
    }

    companion object {
        lateinit var instance: VidoXApp
            private set
    }
}
