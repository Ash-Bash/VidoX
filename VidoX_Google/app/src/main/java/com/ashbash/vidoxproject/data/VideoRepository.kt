package com.ashbash.vidoxproject.data

import com.ashbash.vidoxproject.util.FileStorage
import kotlinx.coroutines.flow.Flow

class VideoRepository(
    private val dao: DownloadedVideoDao,
    private val fileStorage: FileStorage
) {
    fun observeAll(): Flow<List<DownloadedVideo>> = dao.observeAll()
    fun observePinned(): Flow<List<DownloadedVideo>> = dao.observePinned()
    fun observeById(id: String): Flow<DownloadedVideo?> = dao.observeById(id)
    fun observeCount(): Flow<Int> = dao.observeCount()
    fun observePinnedCount(): Flow<Int> = dao.observePinnedCount()

    suspend fun insert(video: DownloadedVideo) = dao.insert(video)
    suspend fun update(video: DownloadedVideo) = dao.update(video)

    suspend fun delete(video: DownloadedVideo) {
        val videoFile = fileStorage.resolvedFile(video.localFilePath)
        fileStorage.removeThumbnailCacheForVideo(videoFile)
        fileStorage.removeFile(video.localFilePath)
        video.thumbnailPath?.let { fileStorage.removeFile(it) }
        dao.delete(video)
    }

    suspend fun togglePinned(video: DownloadedVideo) {
        dao.update(video.toggledPinned())
    }

    suspend fun getById(id: String): DownloadedVideo? = dao.getById(id)
}
