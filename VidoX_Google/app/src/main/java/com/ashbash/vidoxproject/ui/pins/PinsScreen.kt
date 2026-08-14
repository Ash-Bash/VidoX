package com.ashbash.vidoxproject.ui.pins

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ashbash.vidoxproject.VidoXApp
import com.ashbash.vidoxproject.ui.shared.EmptyStateView
import com.ashbash.vidoxproject.ui.shared.LargeTitleHeader
import com.ashbash.vidoxproject.ui.shared.VideoActionsMenu
import com.ashbash.vidoxproject.ui.shared.VideoRowView
import com.ashbash.vidoxproject.ui.shared.compactScrollBottomPadding

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PinsScreen(
    onOpenDownloader: () -> Unit,
    onOpenVideo: (String) -> Unit,
    onBrowseLibrary: () -> Unit,
    showDownloadButton: Boolean = true
) {
    val pinned by VidoXApp.instance.repository.observePinned()
        .collectAsStateWithLifecycle(initialValue = emptyList())

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        LargeTitleHeader(
            title = "Pins",
            showDownload = showDownloadButton,
            onDownload = onOpenDownloader
        )

        if (pinned.isEmpty()) {
            EmptyStateView(
                icon = Icons.Default.PushPin,
                title = "No Pins Yet",
                message = "Pin videos from the Library with the context menu or detail screen. Pinned items show up here and in the sidebar on larger devices.",
                actionTitle = "Browse Library",
                onAction = onBrowseLibrary
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = compactScrollBottomPadding()
            ) {
                items(pinned, key = { it.id }) { video ->
                    var menu by remember(video.id) { mutableStateOf(false) }
                    Box {
                        VideoRowView(
                            video = video,
                            modifier = Modifier.combinedClickable(
                                onClick = { onOpenVideo(video.id) },
                                onLongClick = { menu = true }
                            )
                        )
                        VideoActionsMenu(
                            video = video,
                            expanded = menu,
                            onDismiss = { menu = false },
                            onOpen = { onOpenVideo(video.id) }
                        )
                    }
                }
            }
        }
    }
}
