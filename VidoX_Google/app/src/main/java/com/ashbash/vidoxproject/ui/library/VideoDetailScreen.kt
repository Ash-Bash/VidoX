package com.ashbash.vidoxproject.ui.library

import android.content.Intent
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.PushPin
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.ashbash.vidoxproject.VidoXApp
import com.ashbash.vidoxproject.services.export.VideoExportService
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
    var alert by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }

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

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp)
        ) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        layoutParams = FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT
                        )
                        this.player = player
                        useController = true
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
            )

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
                    "File missing on disk. Delete this entry or download again.",
                    color = MaterialTheme.colorScheme.error
                )
            }

            Spacer(modifier = Modifier.height(20.dp))
            Row {
                Button(onClick = {
                    scope.launch {
                        app.repository.togglePinned(current)
                    }
                }) {
                    Icon(Icons.Default.PushPin, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(if (current.isPinned) "Unpin" else "Pin")
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
