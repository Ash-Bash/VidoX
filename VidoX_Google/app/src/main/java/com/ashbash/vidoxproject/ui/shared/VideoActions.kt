package com.ashbash.vidoxproject.ui.shared

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.ashbash.vidoxproject.VidoXApp
import com.ashbash.vidoxproject.data.DownloadedVideo
import com.ashbash.vidoxproject.services.export.ExportError
import com.ashbash.vidoxproject.services.export.VideoExportService
import kotlinx.coroutines.launch

@Composable
fun VideoActionsMenu(
    video: DownloadedVideo,
    expanded: Boolean,
    onDismiss: () -> Unit,
    onOpen: (() -> Unit)? = null,
    onChanged: () -> Unit = {}
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val app = VidoXApp.instance
    val export = remember { VideoExportService(context) }
    var alert by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }

    val createDoc = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("video/*")
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            try {
                val file = app.fileStorage.resolvedFile(video.localFilePath)
                export.copyToUri(file, uri)
                alert = "Saved a copy. The original stays in VidoX."
            } catch (e: Exception) {
                if (e !is ExportError.SaveCancelled) {
                    alert = e.message
                }
            }
        }
    }

    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        if (onOpen != null) {
            DropdownMenuItem(
                text = { Text("Open") },
                onClick = {
                    onDismiss()
                    onOpen()
                }
            )
        }
        DropdownMenuItem(
            text = { Text(if (video.isPinned) "Unpin" else "Pin") },
            onClick = {
                onDismiss()
                scope.launch {
                    app.repository.togglePinned(video)
                    onChanged()
                }
            },
            leadingIcon = { Icon(Icons.Default.PushPin, contentDescription = null) }
        )
        DropdownMenuItem(
            text = { Text("Save to Gallery") },
            onClick = {
                onDismiss()
                scope.launch {
                    try {
                        val file = app.fileStorage.resolvedFile(video.localFilePath)
                        export.saveToGallery(file, "${video.title}.${video.fileExtension}")
                        alert = "Saved a copy to Gallery. The original stays in VidoX."
                    } catch (e: Exception) {
                        alert = e.message
                    }
                }
            },
            leadingIcon = { Icon(Icons.Default.Photo, contentDescription = null) }
        )
        DropdownMenuItem(
            text = { Text("Share") },
            onClick = {
                onDismiss()
                try {
                    val file = app.fileStorage.resolvedFile(video.localFilePath)
                    val intent = Intent.createChooser(export.shareIntent(file), "Share video")
                    context.startActivity(intent)
                } catch (e: Exception) {
                    alert = e.message
                }
            },
            leadingIcon = { Icon(Icons.Default.Share, contentDescription = null) }
        )
        DropdownMenuItem(
            text = { Text("Save to Files…") },
            onClick = {
                onDismiss()
                createDoc.launch("${video.title}.${video.fileExtension}")
            },
            leadingIcon = { Icon(Icons.Default.Folder, contentDescription = null) }
        )
        DropdownMenuItem(
            text = { Text("Delete from Library") },
            onClick = {
                onDismiss()
                confirmDelete = true
            },
            leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null) }
        )
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete this video?") },
            text = {
                Text("Removes the file from VidoX storage only. Items you already saved to Gallery or Files are not deleted.")
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    scope.launch {
                        app.repository.delete(video)
                        onChanged()
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
