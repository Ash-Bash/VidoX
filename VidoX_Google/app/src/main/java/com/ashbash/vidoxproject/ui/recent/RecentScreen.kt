package com.ashbash.vidoxproject.ui.recent

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
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
fun RecentScreen(
    onOpenDownloader: () -> Unit,
    onOpenVideo: (String) -> Unit,
    showDownloadButton: Boolean = true
) {
    val videos by VidoXApp.instance.repository.observeAll()
        .collectAsStateWithLifecycle(initialValue = emptyList())
    val recent = videos.take(50)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        LargeTitleHeader(
            title = "Recent",
            showDownload = showDownloadButton,
            onDownload = onOpenDownloader
        )

        if (recent.isEmpty()) {
            EmptyStateView(
                icon = Icons.Default.AccessTime,
                title = "No Recent Downloads",
                message = "Videos you download stay in VidoX until you save them to Gallery or Files.",
                actionTitle = "Download a Video",
                onAction = onOpenDownloader
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = compactScrollBottomPadding()
            ) {
                items(recent, key = { it.id }) { video ->
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
