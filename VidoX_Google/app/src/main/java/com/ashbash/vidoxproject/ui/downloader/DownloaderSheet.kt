package com.ashbash.vidoxproject.ui.downloader

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.ashbash.vidoxproject.models.VideoFormat
import com.ashbash.vidoxproject.models.VideoMetadata
import com.ashbash.vidoxproject.ui.shared.PlatformBadge

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloaderSheet(
    onDismiss: () -> Unit,
    viewModel: DownloaderViewModel = viewModel()
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val clipboard = LocalClipboardManager.current
    val dismissAndReset = remember(viewModel, onDismiss) {
        {
            viewModel.reset()
            onDismiss()
        }
    }

    DisposableEffect(viewModel) {
        onDispose { viewModel.reset() }
    }

    ModalBottomSheet(
        onDismissRequest = dismissAndReset,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                SheetPillButton(label = "Cancel", onClick = dismissAndReset)
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    "Download",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.weight(1f))
                SheetPillButton(
                    label = if (state.isDownloading) "…" else "Download",
                    onClick = {
                        // Dismiss only — DisposableEffect resets after the sheet leaves composition.
                        viewModel.startDownload(onSuccess = onDismiss)
                    },
                    enabled = state.canDownload && !state.isDownloading,
                    emphasized = state.canDownload
                )
            }

            Spacer(modifier = Modifier.height(20.dp))

            Text("Video link", style = MaterialTheme.typography.titleSmall)
            Spacer(modifier = Modifier.height(8.dp))
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = MaterialTheme.colorScheme.surface
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp)
                ) {
                    OutlinedTextField(
                        value = state.urlText,
                        onValueChange = viewModel::updateUrl,
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("https://…") },
                        singleLine = true,
                        leadingIcon = {
                            Icon(Icons.Default.Link, contentDescription = null)
                        },
                        trailingIcon = {
                            IconButton(onClick = {
                                clipboard.getText()?.text?.let(viewModel::updateUrl)
                            }) {
                                Icon(
                                    Icons.Default.ContentPaste,
                                    contentDescription = "Paste",
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            }
                        },
                        shape = RoundedCornerShape(12.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f),
                            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f),
                            unfocusedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0f),
                            focusedBorderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.4f)
                        )
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Button(
                        onClick = viewModel::fetchMetadata,
                        enabled = state.urlText.isNotBlank() && !state.isExtracting,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        if (state.isExtracting) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                color = MaterialTheme.colorScheme.onPrimary,
                                strokeWidth = 2.dp
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Looking up…")
                        } else {
                            Text("Fetch Info")
                        }
                    }
                }
            }

            state.errorMessage?.let { error ->
                Spacer(modifier = Modifier.height(12.dp))
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = RoundedCornerShape(14.dp)
                ) {
                    Text(
                        error,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            state.metadata?.let { metadata ->
                Spacer(modifier = Modifier.height(12.dp))
                MetadataCard(metadata)
                if (metadata.allowsRealDownload) {
                    Spacer(modifier = Modifier.height(12.dp))
                    FormatPicker(
                        formats = metadata.formats,
                        selectedId = state.selectedFormatID,
                        onSelect = viewModel::selectFormat
                    )
                    if (metadata.usesYTDLP) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            "Using sideload download engine (yt-dlp).",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.tertiary
                        )
                    }
                } else {
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        "Preview only in this build. Enable standalone social downloads to save the file.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            if (state.isDownloading) {
                Spacer(modifier = Modifier.height(16.dp))
                Text(state.progressLabel, style = MaterialTheme.typography.bodyMedium)
                Spacer(modifier = Modifier.height(8.dp))
                val fraction = state.progressFraction
                if (fraction != null) {
                    LinearProgressIndicator(
                        progress = { fraction.coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth()
                    )
                } else {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
            }

            if (state.metadata == null && !state.isExtracting && state.errorMessage == null) {
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    "Paste a link from YouTube, X, Instagram, Facebook, TikTok, Vimeo, and more — or a direct .mp4 URL.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun SheetPillButton(
    label: String,
    onClick: () -> Unit,
    enabled: Boolean = true,
    emphasized: Boolean = false
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(20.dp),
        color = if (emphasized) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)
        } else {
            MaterialTheme.colorScheme.surfaceVariant
        }
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
            style = MaterialTheme.typography.labelLarge,
            color = if (emphasized) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurface
            },
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
private fun MetadataCard(metadata: VideoMetadata) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surface
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            if (metadata.thumbnailURL != null) {
                AsyncImage(
                    model = metadata.thumbnailURL.toString(),
                    contentDescription = null,
                    modifier = Modifier
                        .width(88.dp)
                        .height(66.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                    contentScale = ContentScale.Crop
                )
                Spacer(modifier = Modifier.width(12.dp))
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(metadata.title, style = MaterialTheme.typography.titleSmall)
                metadata.author?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Spacer(modifier = Modifier.height(6.dp))
                PlatformBadge(metadata.platform)
            }
        }
    }
}

@Composable
private fun FormatPicker(
    formats: List<VideoFormat>,
    selectedId: String?,
    onSelect: (String) -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text("Format", style = MaterialTheme.typography.titleSmall)
        Spacer(modifier = Modifier.height(8.dp))
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            color = MaterialTheme.colorScheme.surface
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp)
            ) {
                formats.forEach { format ->
                    val selected = format.id == selectedId
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(
                                if (selected) {
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                                } else {
                                    MaterialTheme.colorScheme.surface
                                }
                            )
                            .selectable(
                                selected = selected,
                                onClick = { onSelect(format.id) }
                            )
                            .padding(horizontal = 12.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            if (selected) Icons.Default.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
                            contentDescription = null,
                            tint = if (selected) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                            modifier = Modifier.size(22.dp)
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        Text(
                            format.label,
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyLarge
                        )
                        if (format.label.contains("audio", ignoreCase = true) ||
                            format.id.contains("audio", ignoreCase = true)
                        ) {
                            Surface(
                                shape = RoundedCornerShape(6.dp),
                                color = MaterialTheme.colorScheme.surfaceVariant
                            ) {
                                Text(
                                    "Audio",
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
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
}
