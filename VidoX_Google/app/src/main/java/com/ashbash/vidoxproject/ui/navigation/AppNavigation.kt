package com.ashbash.vidoxproject.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.ViewModel
import com.ashbash.vidoxproject.ui.library.LibraryLayoutMode
import com.ashbash.vidoxproject.ui.library.LibrarySortMode

enum class AppDestination(
    val title: String,
    val icon: ImageVector,
    val accentColor: Color
) {
    Library("Library", Icons.Filled.Movie, Color(0f, 0.48f, 1f)),
    Pins("Pins", Icons.Filled.PushPin, Color(1f, 0.58f, 0f)),
    Settings("Settings", Icons.Filled.Settings, Color(0.56f, 0.56f, 0.58f))
}

sealed interface SplitSidebarSelection {
    data class Destination(val destination: AppDestination) : SplitSidebarSelection
    data class PinnedVideo(val id: String) : SplitSidebarSelection
}

/** Shared presentation state for destinations and the download sheet. */
class AppNavigationState : ViewModel() {
    var selectedDestination by mutableStateOf(AppDestination.Library)
    var splitSelection by mutableStateOf<SplitSidebarSelection>(
        SplitSidebarSelection.Destination(AppDestination.Library)
    )
    var isDownloaderPresented by mutableStateOf(false)
    var isOnboardingPresented by mutableStateOf(false)
    var isWhatsNewPresented by mutableStateOf(false)
    var selectedVideoId by mutableStateOf<String?>(null)
    var libraryLayoutMode by mutableStateOf(LibraryLayoutMode.Grid)
    var librarySortMode by mutableStateOf(LibrarySortMode.Newest)

    fun openDownloader() {
        isDownloaderPresented = true
    }

    fun closeDownloader() {
        isDownloaderPresented = false
    }

    fun showOnboarding() {
        isOnboardingPresented = true
    }

    fun finishOnboarding() {
        isOnboardingPresented = false
    }

    fun showWhatsNew() {
        isWhatsNewPresented = true
    }

    fun finishWhatsNew() {
        isWhatsNewPresented = false
    }

    fun selectDestination(destination: AppDestination) {
        selectedDestination = destination
        splitSelection = SplitSidebarSelection.Destination(destination)
        selectedVideoId = null
    }
}
