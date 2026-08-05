package com.ashbash.vidoxproject.ui.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.ashbash.vidoxproject.VidoXApp
import com.ashbash.vidoxproject.data.DownloadedVideo
import com.ashbash.vidoxproject.models.VideoPlatform
import com.ashbash.vidoxproject.util.VideoThumbnailLoader
import java.io.File
import java.util.concurrent.TimeUnit

@Composable
fun EmptyStateView(
    icon: ImageVector,
    title: String,
    message: String,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 36.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f)
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        if (actionTitle != null && onAction != null) {
            Spacer(modifier = Modifier.height(20.dp))
            Button(
                onClick = onAction,
                shape = RoundedCornerShape(22.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary
                )
            ) {
                Text(actionTitle)
            }
        }
    }
}

@Composable
fun PlatformBadge(platform: VideoPlatform) {
    Surface(
        color = platform.accentColor.copy(alpha = 0.15f),
        shape = RoundedCornerShape(6.dp)
    ) {
        Text(
            text = platform.displayName,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelMedium,
            color = platform.accentColor
        )
    }
}

@Composable
fun VideoThumbnailView(
    file: File?,
    modifier: Modifier = Modifier,
    cornerRadius: Int = 10,
    showPlayBadge: Boolean = false,
    showPinnedBadge: Boolean = false,
    savedThumbnail: File? = null
) {
    val shape = RoundedCornerShape(cornerRadius.dp)
    val cacheDir = VidoXApp.instance.fileStorage.thumbnailsDirectory
    var thumbFile by remember(file?.absolutePath, savedThumbnail?.absolutePath) {
        mutableStateOf(
            savedThumbnail?.takeIf { it.exists() }
                ?: file?.let {
                    VideoThumbnailLoader.cacheFileFor(it, cacheDir)
                        .takeIf { cached -> cached.exists() && cached.length() > 0 }
                }
        )
    }
    var failed by remember(file?.absolutePath, savedThumbnail?.absolutePath) {
        mutableStateOf(false)
    }

    LaunchedEffect(file?.absolutePath, savedThumbnail?.absolutePath) {
        if (savedThumbnail != null && savedThumbnail.exists()) {
            thumbFile = savedThumbnail
            failed = false
            return@LaunchedEffect
        }
        val video = file
        if (video == null || !video.exists()) {
            thumbFile = null
            failed = true
            return@LaunchedEffect
        }
        val existing = VideoThumbnailLoader.cacheFileFor(video, cacheDir)
        if (existing.exists() && existing.length() > 0L) {
            thumbFile = existing
            failed = false
            return@LaunchedEffect
        }
        val generated = VideoThumbnailLoader.cachedOrGenerate(video, cacheDir)
        thumbFile = generated
        failed = generated == null
    }

    Box(
        modifier = modifier
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceVariant)
    ) {
        when {
            thumbFile != null && thumbFile!!.exists() -> {
                AsyncImage(
                    model = thumbFile,
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop
                )
            }
            failed || file == null || !file.exists() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Icon(
                        Icons.Default.Movie,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            else -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp
                    )
                }
            }
        }
        if (showPlayBadge || showPinnedBadge) {
            Row(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(6.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                if (showPinnedBadge) {
                    Box(
                        modifier = Modifier
                            .size(20.dp)
                            .background(Color(0xFFE67E22).copy(alpha = 0.9f), CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            Icons.Default.PushPin,
                            contentDescription = null,
                            modifier = Modifier.size(10.dp),
                            tint = Color.White
                        )
                    }
                }
                if (showPlayBadge) {
                    val missing = file == null || !file.exists()
                    Box(
                        modifier = Modifier
                            .size(20.dp)
                            .background(
                                if (missing) Color(0xFFFF9F0A).copy(alpha = 0.95f)
                                else Color.Black.copy(alpha = 0.45f),
                                CircleShape
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            if (missing) Icons.Default.Warning else Icons.Default.PlayArrow,
                            contentDescription = null,
                            modifier = Modifier.size(12.dp),
                            tint = Color.White
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun VideoRowView(
    video: DownloadedVideo,
    modifier: Modifier = Modifier,
    showChevron: Boolean = true
) {
    val storage = VidoXApp.instance.fileStorage
    val file = storage.resolvedFile(video.localFilePath)
    val sizeLabel = storage.formatByteCount(
        if (file.exists()) file.length() else video.fileSize
    )
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            VideoThumbnailView(
                file = file,
                savedThumbnail = storage.resolvedThumbnail(video.thumbnailPath),
                modifier = Modifier.size(64.dp),
                cornerRadius = 8,
                showPlayBadge = true
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (video.isPinned) {
                        Icon(
                            Icons.Default.PushPin,
                            contentDescription = null,
                            modifier = Modifier.size(12.dp),
                            tint = Color(0xFFFF9F0A)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                    }
                    Text(
                        video.title,
                        style = MaterialTheme.typography.titleSmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    if (!file.exists()) {
                        "${video.platform.displayName} · Missing file"
                    } else {
                        "${video.platform.displayName} · ${formatRelativeTime(video.downloadedAt)} · $sizeLabel"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = if (!file.exists()) {
                        Color(0xFFFF9F0A)
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (showChevron) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f)
                )
            }
        }
        HorizontalDivider(
            modifier = Modifier.padding(start = 92.dp),
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)
        )
    }
}

@Composable
fun VideoGridItemView(video: DownloadedVideo, modifier: Modifier = Modifier) {
    val storage = VidoXApp.instance.fileStorage
    val file = storage.resolvedFile(video.localFilePath)
    val missing = !file.exists()
    val sizeLabel = storage.formatByteCount(
        if (!missing) file.length() else video.fileSize
    )
    Column(modifier = modifier) {
        VideoThumbnailView(
            file = file,
            savedThumbnail = storage.resolvedThumbnail(video.thumbnailPath),
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f),
            cornerRadius = 10,
            showPlayBadge = true,
            showPinnedBadge = video.isPinned
        )
        Spacer(modifier = Modifier.height(6.dp))
        // Reserve 2 title lines so every grid cell stays the same height in a row.
        Text(
            video.title,
            style = MaterialTheme.typography.labelLarge,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .height(36.dp)
        )
        Text(
            if (missing) {
                "${video.platform.displayName} · Missing file"
            } else {
                "${video.platform.displayName} · $sizeLabel"
            },
            style = MaterialTheme.typography.labelSmall,
            color = if (missing) {
                Color(0xFFFF9F0A)
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

fun formatRelativeTime(epochMs: Long): String {
    val diff = (System.currentTimeMillis() - epochMs).coerceAtLeast(0L)
    val minutes = TimeUnit.MILLISECONDS.toMinutes(diff)
    val hours = TimeUnit.MILLISECONDS.toHours(diff)
    val days = TimeUnit.MILLISECONDS.toDays(diff)
    return when {
        minutes < 1 -> "Just now"
        minutes < 60 -> "$minutes min ago"
        hours < 24 -> if (hours == 1L) "1 hr ago" else "$hours hrs ago"
        days < 7 -> if (days == 1L) "1 day ago" else "$days days ago"
        days < 30 -> {
            val weeks = days / 7
            if (weeks == 1L) "1 week ago" else "$weeks weeks ago"
        }
        else -> {
            val months = days / 30
            if (months <= 1L) "1 month ago" else "$months months ago"
        }
    }
}
