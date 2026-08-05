package com.ashbash.vidoxproject.ui.library

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ashbash.vidoxproject.VidoXApp
import com.ashbash.vidoxproject.ui.shared.CircleIconButton
import com.ashbash.vidoxproject.ui.shared.EmptyStateView
import com.ashbash.vidoxproject.ui.shared.LargeTitleHeader
import com.ashbash.vidoxproject.ui.shared.ToolbarPill
import com.ashbash.vidoxproject.ui.shared.VideoActionsMenu
import com.ashbash.vidoxproject.ui.shared.VideoGridItemView
import com.ashbash.vidoxproject.ui.shared.VideoRowView
import com.ashbash.vidoxproject.ui.shared.compactScrollBottomPadding

enum class LibraryLayoutMode { Grid, List }

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LibraryScreen(
    onOpenDownloader: () -> Unit,
    onOpenVideo: (String) -> Unit,
    showDownloadButton: Boolean = true
) {
    val videos by VidoXApp.instance.repository.observeAll()
        .collectAsStateWithLifecycle(initialValue = emptyList())
    var layoutMode by remember { mutableStateOf(LibraryLayoutMode.Grid) }
    var sortNewestFirst by remember { mutableStateOf(true) }
    var search by remember { mutableStateOf("") }
    var sortMenu by remember { mutableStateOf(false) }

    val filtered = remember(videos, search, sortNewestFirst) {
        val base = if (search.isBlank()) {
            videos
        } else {
            videos.filter {
                it.title.contains(search, ignoreCase = true) ||
                    (it.author?.contains(search, ignoreCase = true) == true)
            }
        }
        if (sortNewestFirst) base else base.sortedBy { it.title.lowercase() }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        LargeTitleHeader(
            title = "Library",
            showDownload = false,
            actions = {
                ToolbarPill {
                    CircleIconButton(
                        icon = if (layoutMode == LibraryLayoutMode.Grid) {
                            Icons.AutoMirrored.Filled.ViewList
                        } else {
                            Icons.Default.GridView
                        },
                        contentDescription = "Toggle layout",
                        onClick = {
                            layoutMode = if (layoutMode == LibraryLayoutMode.Grid) {
                                LibraryLayoutMode.List
                            } else {
                                LibraryLayoutMode.Grid
                            }
                        }
                    )
                    Box {
                        CircleIconButton(
                            icon = Icons.AutoMirrored.Filled.Sort,
                            contentDescription = "Sort",
                            onClick = { sortMenu = true }
                        )
                        DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                            DropdownMenuItem(
                                text = {
                                    Text(if (sortNewestFirst) "Sort by Title" else "Sort by Newest")
                                },
                                onClick = {
                                    sortNewestFirst = !sortNewestFirst
                                    sortMenu = false
                                }
                            )
                        }
                    }
                    if (showDownloadButton) {
                        CircleIconButton(
                            icon = Icons.Default.Download,
                            contentDescription = "Download",
                            onClick = onOpenDownloader
                        )
                    }
                }
            }
        )

        if (videos.isNotEmpty()) {
            OutlinedTextField(
                value = search,
                onValueChange = { search = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 8.dp),
                placeholder = { Text("Search library") },
                leadingIcon = {
                    Icon(Icons.Default.Search, contentDescription = null)
                },
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0f),
                    focusedBorderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.35f)
                )
            )
        }

        when {
            videos.isEmpty() -> EmptyStateView(
                icon = Icons.Default.Movie,
                title = "Library Empty",
                message = "Downloads stay inside VidoX. Use Save to Gallery or Share / Files when you want a copy elsewhere.",
                actionTitle = "Download a Video",
                onAction = onOpenDownloader
            )
            filtered.isEmpty() -> EmptyStateView(
                icon = Icons.Default.Movie,
                title = "No Results",
                message = "Nothing matches “$search”."
            )
            layoutMode == LibraryLayoutMode.Grid -> {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(112.dp),
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(
                        start = 14.dp,
                        end = 14.dp,
                        top = 12.dp,
                        bottom = 28.dp
                    ),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    items(filtered, key = { it.id }) { video ->
                        var menu by remember(video.id) { mutableStateOf(false) }
                        Box {
                            VideoGridItemView(
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
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = compactScrollBottomPadding()
                ) {
                    items(filtered, key = { it.id }) { video ->
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
}
