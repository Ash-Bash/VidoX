package com.ashbash.vidoxproject.ui.onboarding

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.ashbash.vidoxproject.BuildConfig

data class WhatsNewItem(
    val icon: ImageVector,
    val accent: Color,
    val title: String,
    val message: String
)

object WhatsNewNotes {
    val currentVersion: String
        get() = BuildConfig.VERSION_NAME

    private val releases: List<Pair<String, List<WhatsNewItem>>> = listOf(
        "1.1.0" to listOf(
            WhatsNewItem(
                icon = Icons.Filled.SwapVert,
                accent = Color(0f, 0.48f, 1f),
                title = "Library sorting",
                message = "Sort by newest, title, video size, or social site."
            ),
            WhatsNewItem(
                icon = Icons.Filled.Menu,
                accent = Color(0.35f, 0.34f, 0.84f),
                title = "Desktop menus",
                message = "Download, browse, and sort from the menu bar on tablet and desktop."
            ),
            WhatsNewItem(
                icon = Icons.Filled.CameraAlt,
                accent = Color(0.88f, 0.19f, 0.42f),
                title = "Faster Instagram",
                message = "Instagram and kkinstagram links resolve in parallel, so they load sooner."
            ),
            WhatsNewItem(
                icon = Icons.Filled.GridView,
                accent = Color(1f, 0.58f, 0f),
                title = "Sidebar action cards",
                message = "Library and Settings sit in Reminders-style cards on tablet and desktop."
            ),
            WhatsNewItem(
                icon = Icons.Filled.Settings,
                accent = Color(0.56f, 0.56f, 0.58f),
                title = "Library cleanup",
                message = "Remove video files or wipe the library from Settings, without touching Gallery copies."
            )
        )
    )

    fun itemsAfter(lastSeenVersion: String): List<WhatsNewItem> =
        releases
            .filter { versionIsNewer(it.first, lastSeenVersion) }
            .filter { !versionIsNewer(it.first, currentVersion) }
            .flatMap { it.second }

    fun displayItems(lastSeenVersion: String): List<WhatsNewItem> {
        val newer = itemsAfter(lastSeenVersion)
        return newer.ifEmpty { currentReleaseItems }
    }

    val currentReleaseItems: List<WhatsNewItem>
        get() = releases.lastOrNull { !versionIsNewer(it.first, currentVersion) }?.second.orEmpty()

    fun shouldPresent(lastSeenVersion: String): Boolean =
        lastSeenVersion != currentVersion && itemsAfter(lastSeenVersion).isNotEmpty()

    private fun versionIsNewer(lhs: String, rhs: String): Boolean {
        val left = lhs.split('.').mapNotNull { it.toIntOrNull() }
        val right = rhs.split('.').mapNotNull { it.toIntOrNull() }
        val count = maxOf(left.size, right.size)
        for (index in 0 until count) {
            val a = left.getOrElse(index) { 0 }
            val b = right.getOrElse(index) { 0 }
            if (a != b) return a > b
        }
        return false
    }
}
