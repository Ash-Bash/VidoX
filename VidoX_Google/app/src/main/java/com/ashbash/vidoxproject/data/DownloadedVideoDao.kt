package com.ashbash.vidoxproject.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface DownloadedVideoDao {
    @Query("SELECT * FROM downloaded_videos ORDER BY downloadedAt DESC")
    fun observeAll(): Flow<List<DownloadedVideo>>

    @Query("SELECT * FROM downloaded_videos WHERE isPinned = 1 ORDER BY pinnedAt DESC")
    fun observePinned(): Flow<List<DownloadedVideo>>

    @Query("SELECT * FROM downloaded_videos WHERE id = :id LIMIT 1")
    fun observeById(id: String): Flow<DownloadedVideo?>

    @Query("SELECT * FROM downloaded_videos WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): DownloadedVideo?

    @Query("SELECT COUNT(*) FROM downloaded_videos")
    fun observeCount(): Flow<Int>

    @Query("SELECT COUNT(*) FROM downloaded_videos WHERE isPinned = 1")
    fun observePinnedCount(): Flow<Int>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(video: DownloadedVideo)

    @Update
    suspend fun update(video: DownloadedVideo)

    @Query("SELECT * FROM downloaded_videos")
    suspend fun getAll(): List<DownloadedVideo>

    @Query("DELETE FROM downloaded_videos")
    suspend fun deleteAll()

    @Delete
    suspend fun delete(video: DownloadedVideo)
}
