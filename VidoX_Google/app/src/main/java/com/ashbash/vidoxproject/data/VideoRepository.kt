package com.ashbash.vidoxproject.data

import com.ashbash.vidoxproject.util.FileStorage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

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

    /** Deletes downloaded video files to free space. Library items stay for later redownload. */
    suspend fun removeAllVideoFilesKeepingItems() = withContext(Dispatchers.IO) {
        dao.getAll().forEach { video ->
            fileStorage.removeVideoMediaKeepingRecord(video.localFilePath)
        }
    }

    /** Deletes every library item and its files from VidoX storage. */
    suspend fun deleteAllItemsAndFiles() = withContext(Dispatchers.IO) {
        dao.getAll().forEach { video ->
            val videoFile = fileStorage.resolvedFile(video.localFilePath)
            fileStorage.removeThumbnailCacheForVideo(videoFile)
            fileStorage.removeFile(video.localFilePath)
            video.thumbnailPath?.let { fileStorage.removeFile(it) }
        }
        dao.deleteAll()
        fileStorage.removeAllMediaFiles()
    }

    suspend fun togglePinned(video: DownloadedVideo) {
        dao.update(video.toggledPinned())
    }

    suspend fun getById(id: String): DownloadedVideo? = dao.getById(id)
}
