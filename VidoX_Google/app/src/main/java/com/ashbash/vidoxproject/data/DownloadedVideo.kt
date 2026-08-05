package com.ashbash.vidoxproject.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.ashbash.vidoxproject.models.VideoPlatform
import java.util.UUID

/** Persistent record of a video stored in the local library. */
@Entity(tableName = "downloaded_videos")
data class DownloadedVideo(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val title: String,
    val author: String? = null,
    val sourceURL: String,
    val platformRaw: String,
    val thumbnailPath: String? = null,
    val localFilePath: String,
    val fileExtension: String,
    val downloadedAt: Long = System.currentTimeMillis(),
    val fileSize: Long = 0,
    val isPinned: Boolean = false,
    val pinnedAt: Long? = null
) {
    val platform: VideoPlatform
        get() = VideoPlatform.fromRaw(platformRaw)

    fun toggledPinned(): DownloadedVideo =
        if (isPinned) {
            copy(isPinned = false, pinnedAt = null)
        } else {
            copy(isPinned = true, pinnedAt = System.currentTimeMillis())
        }
}
