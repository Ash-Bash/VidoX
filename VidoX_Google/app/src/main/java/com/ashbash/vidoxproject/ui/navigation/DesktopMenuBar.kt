package com.ashbash.vidoxproject.ui.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.unit.dp
import com.ashbash.vidoxproject.ui.library.LibraryLayoutMode
import com.ashbash.vidoxproject.ui.library.LibrarySortMode

/** In-app menu bar for tablet / ChromeOS / desktop windows (Android has no system menu bar). */
@Composable
fun DesktopMenuBar(
    navigation: AppNavigationState,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(36.dp)
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        MenuBarItem("File") { dismiss ->
            DropdownMenuItem(
                text = { Text("Download Video…") },
                trailingIcon = { ShortcutHint("Ctrl+N") },
                onClick = {
                    navigation.openDownloader()
                    dismiss()
                }
            )
        }
        MenuBarItem("View") { dismiss ->
            LibraryLayoutMode.entries.forEach { mode ->
                DropdownMenuItem(
                    text = { Text(mode.label) },
                    leadingIcon = { MenuCheck(navigation.libraryLayoutMode == mode) },
                    onClick = {
                        navigation.libraryLayoutMode = mode
                        dismiss()
                    }
                )
            }
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            LibrarySortMode.entries.forEach { mode ->
                DropdownMenuItem(
                    text = { Text(mode.menuTitle) },
                    leadingIcon = { MenuCheck(navigation.librarySortMode == mode) },
                    onClick = {
                        navigation.librarySortMode = mode
                        dismiss()
                    }
                )
            }
        }
        MenuBarItem("Go") { dismiss ->
            AppDestination.entries.forEachIndexed { index, destination ->
                DropdownMenuItem(
                    text = { Text(destination.title) },
                    leadingIcon = { MenuCheck(navigation.selectedDestination == destination) },
                    trailingIcon = { ShortcutHint("Ctrl+${index + 1}") },
                    onClick = {
                        navigation.selectDestination(destination)
                        dismiss()
                    }
                )
            }
        }
        Spacer(modifier = Modifier.weight(1f))
    }
}

private val LibraryLayoutMode.label: String
    get() = when (this) {
        LibraryLayoutMode.Grid -> "Grid"
        LibraryLayoutMode.List -> "List"
    }

@Composable
private fun ShortcutHint(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun MenuCheck(selected: Boolean) {
    if (selected) {
        Icon(Icons.Default.Check, contentDescription = null)
    } else {
        Spacer(modifier = Modifier.width(24.dp))
    }
}

@Composable
private fun MenuBarItem(
    title: String,
    content: @Composable (dismiss: () -> Unit) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Text(
            title,
            style = MaterialTheme.typography.labelLarge,
            color = if (expanded) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurface
            },
            modifier = Modifier
                .clip(RoundedCornerShape(6.dp))
                .clickable { expanded = true }
                .padding(horizontal = 10.dp, vertical = 6.dp)
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            content { expanded = false }
        }
    }
}

fun Modifier.vidoxDesktopShortcuts(navigation: AppNavigationState): Modifier =
    onPreviewKeyEvent { event ->
        if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
        if (!event.isCtrlPressed && !event.isMetaPressed) return@onPreviewKeyEvent false
        when (event.key) {
            Key.N -> {
                navigation.openDownloader()
                true
            }
            Key.One -> {
                navigation.selectDestination(AppDestination.Library)
                true
            }
            Key.Two -> {
                navigation.selectDestination(AppDestination.Pins)
                true
            }
            Key.Three -> {
                navigation.selectDestination(AppDestination.Settings)
                true
            }
            else -> false
        }
    }
