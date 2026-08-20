package com.ashbash.vidoxproject.ui.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.activity.ComponentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ashbash.vidoxproject.VidoXApp
import com.ashbash.vidoxproject.ui.downloader.DownloaderSheet
import com.ashbash.vidoxproject.ui.library.LibraryScreen
import com.ashbash.vidoxproject.ui.library.VideoDetailScreen
import com.ashbash.vidoxproject.ui.onboarding.OnboardingScreen
import com.ashbash.vidoxproject.ui.onboarding.OnboardingStore
import com.ashbash.vidoxproject.ui.onboarding.WhatsNewNotes
import com.ashbash.vidoxproject.ui.onboarding.WhatsNewScreen
import com.ashbash.vidoxproject.ui.pins.PinsScreen
import com.ashbash.vidoxproject.ui.settings.SettingsScreen
import com.ashbash.vidoxproject.ui.shared.DownloadCircleButton
import com.ashbash.vidoxproject.ui.shared.FloatingPillNavigationBar
import com.ashbash.vidoxproject.ui.shared.VideoThumbnailView
import com.ashbash.vidoxproject.ui.shared.compactFloatingNavClearance

@OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
@Composable
fun RootShell(navigation: AppNavigationState = viewModel()) {
    val activity = LocalContext.current as ComponentActivity
    val widthClass = calculateWindowSizeClass(activity).widthSizeClass
    val useSplit = widthClass != WindowWidthSizeClass.Compact

    if (navigation.isDownloaderPresented) {
        DownloaderSheet(onDismiss = navigation::closeDownloader)
    }

    LaunchedEffect(Unit) {
        if (!OnboardingStore.isCompleted(activity)) {
            navigation.showOnboarding()
        } else if (WhatsNewNotes.shouldPresent(OnboardingStore.lastSeenVersion(activity))) {
            navigation.showWhatsNew()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        if (useSplit) {
            RegularSplitShell(navigation)
        } else {
            CompactTabShell(navigation)
        }
        if (navigation.isOnboardingPresented) {
            OnboardingScreen(
                onFinished = {
                    OnboardingStore.setCompleted(activity)
                    OnboardingStore.markCurrentVersionSeen(activity)
                    navigation.finishOnboarding()
                }
            )
        }
        if (navigation.isWhatsNewPresented) {
            WhatsNewScreen(
                items = WhatsNewNotes.displayItems(OnboardingStore.lastSeenVersion(activity)),
                onFinished = {
                    OnboardingStore.markCurrentVersionSeen(activity)
                    navigation.finishWhatsNew()
                }
            )
        }
    }
}

@Composable
private fun CompactTabShell(navigation: AppNavigationState) {
    val destinations = AppDestination.entries
    val showingDetail = navigation.selectedVideoId != null

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        val bottomClearance = if (showingDetail) 0.dp else compactFloatingNavClearance()
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(
                    WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Top)
                )
                .padding(bottom = bottomClearance)
        ) {
            CompactContent(navigation)
        }

        if (!showingDetail) {
            FloatingPillNavigationBar(
                destinations = destinations,
                selected = navigation.selectedDestination,
                onSelect = navigation::selectDestination,
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }
    }
}

@Composable
private fun CompactContent(navigation: AppNavigationState) {
    val videoId = navigation.selectedVideoId
    if (videoId != null) {
        VideoDetailScreen(
            videoId = videoId,
            onBack = { navigation.selectedVideoId = null }
        )
        return
    }

    when (navigation.selectedDestination) {
        AppDestination.Library -> LibraryScreen(
            onOpenDownloader = navigation::openDownloader,
            onOpenVideo = { navigation.selectedVideoId = it },
            showDownloadButton = true,
            layoutMode = navigation.libraryLayoutMode,
            onLayoutModeChange = { navigation.libraryLayoutMode = it },
            sortMode = navigation.librarySortMode,
            onSortModeChange = { navigation.librarySortMode = it }
        )
        AppDestination.Pins -> PinsScreen(
            onOpenDownloader = navigation::openDownloader,
            onOpenVideo = { navigation.selectedVideoId = it },
            onBrowseLibrary = { navigation.selectDestination(AppDestination.Library) },
            showDownloadButton = true
        )
        AppDestination.Settings -> SettingsScreen(
            onOpenDownloader = navigation::openDownloader,
            showDownloadButton = true,
            onLibraryWiped = { navigation.selectedVideoId = null },
            onShowOnboarding = navigation::showOnboarding,
            onShowWhatsNew = navigation::showWhatsNew
        )
    }
}

/**
 * Tablet / Chromebook shell — sidebar with Browse + Pinned, detail pane on the right
 * (mirrors Apple NavigationSplitView).
 */
@Composable
private fun RegularSplitShell(navigation: AppNavigationState) {
    val pinned by VidoXApp.instance.repository.observePinned()
        .collectAsStateWithLifecycle(initialValue = emptyList())
    val videos by VidoXApp.instance.repository.observeAll()
        .collectAsStateWithLifecycle(initialValue = emptyList())
    val storage = VidoXApp.instance.fileStorage
    val browseDestinations = listOf(
        AppDestination.Library,
        AppDestination.Settings
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            // safeDrawing includes desktop/ChromeOS caption bars — statusBars alone does not.
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .vidoxDesktopShortcuts(navigation)
    ) {
        DesktopMenuBar(navigation)
        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
        Row(modifier = Modifier.weight(1f).fillMaxSize()) {
        Surface(
            modifier = Modifier
                .width(300.dp)
                .fillMaxHeight(),
            color = MaterialTheme.colorScheme.surface,
            tonalElevation = 1.dp
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 10.dp)
                    .padding(top = 8.dp, bottom = 12.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "VidoX",
                        style = MaterialTheme.typography.headlineMedium,
                        modifier = Modifier.weight(1f)
                    )
                    DownloadCircleButton(onClick = navigation::openDownloader)
                }

                Spacer(modifier = Modifier.height(8.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    browseDestinations.forEach { destination ->
                        val selected = navigation.splitSelection is SplitSidebarSelection.Destination &&
                            (navigation.splitSelection as SplitSidebarSelection.Destination).destination == destination &&
                            navigation.selectedVideoId == null
                        SidebarActionCard(
                            destination = destination,
                            selected = selected,
                            count = if (destination == AppDestination.Library) videos.size else null,
                            onClick = { navigation.selectDestination(destination) },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
                Spacer(modifier = Modifier.height(8.dp))

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.PushPin,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        "Pinned",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))

                if (pinned.isEmpty()) {
                    Text(
                        "Pin videos from Library",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        items(pinned, key = { it.id }) { video ->
                            val selected = navigation.splitSelection is SplitSidebarSelection.PinnedVideo &&
                                (navigation.splitSelection as SplitSidebarSelection.PinnedVideo).id == video.id
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(
                                        if (selected) {
                                            MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                                        } else {
                                            Color.Transparent
                                        }
                                    )
                                    .clickable {
                                        navigation.splitSelection = SplitSidebarSelection.PinnedVideo(video.id)
                                        navigation.selectedVideoId = video.id
                                    }
                                    .padding(horizontal = 8.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                VideoThumbnailView(
                                    file = storage.resolvedFile(video.localFilePath),
                                    savedThumbnail = storage.resolvedThumbnail(video.thumbnailPath),
                                    modifier = Modifier.size(40.dp),
                                    cornerRadius = 6
                                )
                                Spacer(modifier = Modifier.width(10.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        video.title,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        style = MaterialTheme.typography.bodyMedium,
                                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
                                    )
                                    Text(
                                        video.platform.displayName,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        VerticalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))

        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
        ) {
            when (val selection = navigation.splitSelection) {
                is SplitSidebarSelection.Destination -> {
                    navigation.selectedVideoId?.let { id ->
                        VideoDetailScreen(
                            videoId = id,
                            onBack = { navigation.selectedVideoId = null }
                        )
                    } ?: when (selection.destination) {
                        AppDestination.Library -> LibraryScreen(
                            onOpenDownloader = navigation::openDownloader,
                            onOpenVideo = { navigation.selectedVideoId = it },
                            showDownloadButton = false,
                            layoutMode = navigation.libraryLayoutMode,
                            onLayoutModeChange = { navigation.libraryLayoutMode = it },
                            sortMode = navigation.librarySortMode,
                            onSortModeChange = { navigation.librarySortMode = it }
                        )
                        AppDestination.Pins -> PinsScreen(
                            onOpenDownloader = navigation::openDownloader,
                            onOpenVideo = { navigation.selectedVideoId = it },
                            onBrowseLibrary = { navigation.selectDestination(AppDestination.Library) },
                            showDownloadButton = false
                        )
                        AppDestination.Settings -> SettingsScreen(
                            onOpenDownloader = navigation::openDownloader,
                            showDownloadButton = false,
                            onLibraryWiped = { navigation.selectedVideoId = null },
                            onShowOnboarding = navigation::showOnboarding,
                            onShowWhatsNew = navigation::showWhatsNew
                        )
                    }
                }
                is SplitSidebarSelection.PinnedVideo -> {
                    VideoDetailScreen(
                        videoId = selection.id,
                        onBack = { navigation.selectDestination(AppDestination.Library) }
                    )
                }
            }
        }
        }
    }
}

@Composable
private fun SidebarActionCard(
    destination: AppDestination,
    selected: Boolean,
    count: Int?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(
                if (selected) {
                    MaterialTheme.colorScheme.primary.copy(alpha = 0.22f)
                } else {
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
                }
            )
            .clickable(onClick = onClick)
            .padding(8.dp)
            .height(64.dp),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top
        ) {
            Box(
                modifier = Modifier
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(destination.accentColor),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    destination.icon,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(14.dp)
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            if (count != null) {
                Text(
                    count.toString(),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Text(
            destination.title,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold
        )
    }
}
