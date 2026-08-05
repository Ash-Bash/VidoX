package com.ashbash.vidoxproject.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [DownloadedVideo::class], version = 1, exportSchema = false)
abstract class VidoXDatabase : RoomDatabase() {
    abstract fun downloadedVideoDao(): DownloadedVideoDao

    companion object {
        @Volatile
        private var instance: VidoXDatabase? = null

        fun get(context: Context): VidoXDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    VidoXDatabase::class.java,
                    "vidox.db"
                ).build().also { instance = it }
            }
    }
}
