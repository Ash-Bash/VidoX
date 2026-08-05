package com.ashbash.vidoxproject.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTimeFilled
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.ViewModel

enum class AppDestination(
    val title: String,
    val icon: ImageVector
) {
    Recent("Recent", Icons.Filled.AccessTimeFilled),
    Library("Library", Icons.Filled.Movie),
    Pins("Pins", Icons.Filled.PushPin),
    Settings("Settings", Icons.Filled.Settings)
}

sealed interface SplitSidebarSelection {
    data class Destination(val destination: AppDestination) : SplitSidebarSelection
    data class PinnedVideo(val id: String) : SplitSidebarSelection
}

/** Shared presentation state for destinations and the download sheet. */
class AppNavigationState : ViewModel() {
    var selectedDestination by mutableStateOf(AppDestination.Recent)
    var splitSelection by mutableStateOf<SplitSidebarSelection>(
        SplitSidebarSelection.Destination(AppDestination.Recent)
    )
    var isDownloaderPresented by mutableStateOf(false)
    var selectedVideoId by mutableStateOf<String?>(null)

    fun openDownloader() {
        isDownloaderPresented = true
    }

    fun closeDownloader() {
        isDownloaderPresented = false
    }

    fun selectDestination(destination: AppDestination) {
        selectedDestination = destination
        splitSelection = SplitSidebarSelection.Destination(destination)
        selectedVideoId = null
    }
}
