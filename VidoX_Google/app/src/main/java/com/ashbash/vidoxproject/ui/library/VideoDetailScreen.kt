package com.ashbash.vidoxproject.ui.library

import android.content.Intent
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.ashbash.vidoxproject.VidoXApp
import com.ashbash.vidoxproject.services.download.VideoRedownloader
import com.ashbash.vidoxproject.services.export.VideoExportService
import com.ashbash.vidoxproject.ui.shared.BusyProgressDialog
import com.ashbash.vidoxproject.ui.shared.PlatformBadge
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoDetailScreen(
    videoId: String,
    onBack: () -> Unit
) {
    val video by VidoXApp.instance.repository.observeById(videoId)
        .collectAsStateWithLifecycle(initialValue = null)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val app = VidoXApp.instance
    val export = remember { VideoExportService(context) }
    val redownloader = remember { VideoRedownloader(app) }
    var alert by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var isRedownloading by remember { mutableStateOf(false) }
    var redownloadLabel by remember { mutableStateOf("Looking up…") }
    var redownloadFraction by remember { mutableStateOf<Float?>(null) }
    var isFullscreen by remember(videoId) { mutableStateOf(false) }

    val createDoc = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("video/*")
    ) { uri ->
        val current = video ?: return@rememberLauncherForActivityResult
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            try {
                export.copyToUri(app.fileStorage.resolvedFile(current.localFilePath), uri)
                alert = "Saved a copy. The original stays in VidoX."
            } catch (e: Exception) {
                alert = e.message
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(video?.title ?: "Video") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        val current = video
        if (current == null) {
            Text("Video not found", modifier = Modifier.padding(padding).padding(20.dp))
            return@Scaffold
        }

        val file = app.fileStorage.resolvedFile(current.localFilePath)
        val player = remember(current.id) {
            ExoPlayer.Builder(context).build().apply {
                if (file.exists()) {
                    setMediaItem(MediaItem.fromUri(file.absolutePath))
                    prepare()
                }
            }
        }
        DisposableEffect(player) {
            onDispose { player.release() }
        }

        BackHandler(enabled = isFullscreen) {
            isFullscreen = false
        }

        if (isFullscreen) {
            Dialog(
                onDismissRequest = { isFullscreen = false },
                properties = DialogProperties(
                    dismissOnBackPress = true,
                    dismissOnClickOutside = false,
                    usePlatformDefaultWidth = false,
                    decorFitsSystemWindows = false
                )
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black)
                ) {
                    LibraryPlayerView(
                        player = player,
                        isFullscreen = true,
                        onFullscreenChange = { isFullscreen = it },
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp)
        ) {
            if (isFullscreen) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f)
                        .background(Color.Black)
                )
            } else {
                LibraryPlayerView(
                    player = player,
                    isFullscreen = false,
                    onFullscreenChange = { isFullscreen = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f)
                )
            }

            Spacer(modifier = Modifier.height(16.dp))
            Text(current.title, style = MaterialTheme.typography.headlineSmall)
            current.author?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(modifier = Modifier.height(8.dp))
            PlatformBadge(current.platform)
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                app.fileStorage.formatByteCount(
                    if (file.exists()) file.length() else current.fileSize
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (!file.exists()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "File missing on disk. Redownload to restore it without creating a duplicate.",
                    color = MaterialTheme.colorScheme.error
                )
            }

            Spacer(modifier = Modifier.height(16.dp))
            val actionPadding = PaddingValues(horizontal = 8.dp, vertical = 10.dp)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (file.exists()) {
                    Button(
                        onClick = {
                            if (player.playbackState == Player.STATE_ENDED) {
                                player.seekTo(0)
                            }
                            player.play()
                        },
                        modifier = Modifier.weight(1f),
                        contentPadding = actionPadding
                    ) {
                        EqualWidthButtonLabel(Icons.Default.PlayArrow, "Play")
                    }
                    OutlinedButton(
                        onClick = { isFullscreen = true },
                        modifier = Modifier.weight(1f),
                        contentPadding = actionPadding
                    ) {
                        EqualWidthButtonLabel(Icons.Default.Fullscreen, "Full Screen")
                    }
                } else {
                    Button(
                        onClick = {
                            isRedownloading = true
                            redownloadLabel = "Looking up…"
                            redownloadFraction = null
                            scope.launch {
                                try {
                                    redownloader.redownload(current) { label, fraction ->
                                        redownloadLabel = label
                                        redownloadFraction = fraction
                                    }
                                    alert = "Redownloaded successfully."
                                } catch (e: Exception) {
                                    alert = e.message ?: "Redownload failed."
                                } finally {
                                    isRedownloading = false
                                }
                            }
                        },
                        enabled = !isRedownloading,
                        modifier = Modifier.weight(1f),
                        contentPadding = actionPadding
                    ) {
                        EqualWidthButtonLabel(Icons.Default.Refresh, "Redownload")
                    }
                }
                OutlinedButton(
                    onClick = {
                        scope.launch {
                            app.repository.togglePinned(current)
                        }
                    },
                    modifier = Modifier.weight(1f),
                    contentPadding = actionPadding
                ) {
                    EqualWidthButtonLabel(
                        Icons.Default.PushPin,
                        if (current.isPinned) "Unpin" else "Pin"
                    )
                }
            }
            Spacer(modifier = Modifier.height(10.dp))
            OutlinedButton(
                onClick = {
                    scope.launch {
                        try {
                            export.saveToGallery(file, "${current.title}.${current.fileExtension}")
                            alert = "Saved a copy to Gallery. The original stays in VidoX."
                        } catch (e: Exception) {
                            alert = e.message
                        }
                    }
                },
                enabled = file.exists(),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Photo, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Save to Gallery")
            }
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedButton(
                onClick = {
                    try {
                        context.startActivity(
                            Intent.createChooser(export.shareIntent(file), "Share video")
                        )
                    } catch (e: Exception) {
                        alert = e.message
                    }
                },
                enabled = file.exists(),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Share, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Share")
            }
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedButton(
                onClick = { createDoc.launch("${current.title}.${current.fileExtension}") },
                enabled = file.exists(),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Folder, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Save to Files…")
            }
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedButton(
                onClick = { confirmDelete = true },
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Delete, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Delete from Library")
            }
        }
    }

    if (isRedownloading) {
        BusyProgressDialog(
            label = redownloadLabel,
            progressFraction = redownloadFraction
        )
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete this video?") },
            text = {
                Text("The file will be removed from VidoX storage. Copies already in Gallery or Files are kept.")
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    val current = video ?: return@TextButton
                    scope.launch {
                        app.repository.delete(current)
                        onBack()
                    }
                }) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
            }
        )
    }

    alert?.let { message ->
        AlertDialog(
            onDismissRequest = { alert = null },
            title = { Text("Notice") },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { alert = null }) { Text("OK") }
            }
        )
    }
}

@Composable
private fun EqualWidthButtonLabel(icon: ImageVector, text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(16.dp))
        Spacer(modifier = Modifier.width(5.dp))
        Text(
            text,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/** Single ExoPlayer surface — inline or fullscreen, never both at once. */
@Composable
private fun LibraryPlayerView(
    player: ExoPlayer,
    isFullscreen: Boolean,
    onFullscreenChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    if (isFullscreen) {
                        ViewGroup.LayoutParams.MATCH_PARENT
                    } else {
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    }
                )
                useController = true
                this.player = player
                setFullscreenButtonState(isFullscreen)
                setFullscreenButtonClickListener { goingFullscreen ->
                    onFullscreenChange(goingFullscreen)
                }
            }
        },
        update = { view ->
            if (view.player !== player) {
                view.player = player
            }
            view.setFullscreenButtonState(isFullscreen)
            view.setFullscreenButtonClickListener { goingFullscreen ->
                onFullscreenChange(goingFullscreen)
            }
        },
        onRelease = { view ->
            view.player = null
        },
        modifier = modifier
    )
}
