package com.ashbash.vidoxproject.ui.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.ashbash.vidoxproject.R

private data class OnboardingPage(
    val icon: ImageVector,
    val accent: Color,
    val title: String,
    val message: String,
    val usesAppIcon: Boolean = false
)

/** First-launch welcome, styled like Apple’s built-in app introductions. */
@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    val pages = remember {
        listOf(
            OnboardingPage(
                icon = Icons.Filled.PlayArrow,
                accent = Color(0f, 0.48f, 1f),
                title = "Welcome to VidoX",
                message = "Your videos, in one place. Download a link, keep it in your private library, and play it here.",
                usesAppIcon = true
            ),
            OnboardingPage(
                icon = Icons.Filled.Download,
                accent = Color(0.20f, 0.78f, 0.35f),
                title = "Paste a link",
                message = "Drop in YouTube, Instagram, TikTok, and other supported links. VidoX fetches the video into this app — not your Gallery."
            ),
            OnboardingPage(
                icon = Icons.Filled.Movie,
                accent = Color(0f, 0.48f, 1f),
                title = "Browse your library",
                message = "Search, switch grid or list, and sort by newest, title, size, or site."
            ),
            OnboardingPage(
                icon = Icons.Filled.PushPin,
                accent = Color(1f, 0.58f, 0f),
                title = "Pin favourites",
                message = "Pin videos you want close. They appear in Pins, and in the sidebar on tablet and desktop."
            ),
            OnboardingPage(
                icon = Icons.Filled.Share,
                accent = Color(0.35f, 0.34f, 0.84f),
                title = "Keep or share a copy",
                message = "Downloads stay in VidoX. Save to Gallery, share, or export to Files only when you want a copy elsewhere."
            ),
            OnboardingPage(
                icon = Icons.Filled.CheckCircle,
                accent = Color(0.20f, 0.78f, 0.35f),
                title = "You’re ready",
                message = "Start with Download, or open the library. You can replay this guide anytime from Settings."
            )
        )
    }
    var pageIndex by remember { mutableIntStateOf(0) }
    val page = pages[pageIndex]
    val isLast = pageIndex == pages.lastIndex

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = 24.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
            ) {
                if (pageIndex > 0) {
                    GlassCircleButton(
                        icon = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                        onClick = { pageIndex -= 1 },
                        modifier = Modifier.align(Alignment.CenterStart)
                    )
                }
                if (!isLast) {
                    GlassCircleButton(
                        icon = Icons.Filled.Close,
                        contentDescription = "Skip",
                        onClick = onFinished,
                        modifier = Modifier.align(Alignment.CenterEnd)
                    )
                }
            }

            AnimatedContent(
                targetState = pageIndex,
                modifier = Modifier.weight(1f),
                transitionSpec = {
                    if (targetState > initialState) {
                        (slideInHorizontally { it / 3 } + fadeIn())
                            .togetherWith(slideOutHorizontally { -it / 3 } + fadeOut())
                    } else {
                        (slideInHorizontally { -it / 3 } + fadeIn())
                            .togetherWith(slideOutHorizontally { it / 3 } + fadeOut())
                    }
                },
                label = "onboarding-page"
            ) { index ->
                val current = pages[index]
                Column(
                    modifier = Modifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    if (current.usesAppIcon) {
                        Image(
                            painter = painterResource(R.drawable.ic_app_icon),
                            contentDescription = null,
                            modifier = Modifier
                                .size(88.dp)
                                .clip(RoundedCornerShape(20.dp))
                        )
                    } else {
                        Box(
                            modifier = Modifier
                                .size(72.dp)
                                .clip(CircleShape)
                                .background(current.accent),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                current.icon,
                                contentDescription = null,
                                tint = Color.White,
                                modifier = Modifier.size(32.dp)
                            )
                        }
                    }
                    Spacer(modifier = Modifier.height(20.dp))
                    Text(
                        current.title,
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.height(10.dp))
                    Text(
                        current.message,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(0.92f)
                    )
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 20.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                pages.forEachIndexed { index, _ ->
                    val selected = index == pageIndex
                    Box(
                        modifier = Modifier
                            .padding(horizontal = 3.dp)
                            .height(6.dp)
                            .width(if (selected) 16.dp else 6.dp)
                            .clip(CircleShape)
                            .background(
                                if (selected) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.18f)
                                }
                            )
                    )
                }
            }

            Button(
                onClick = {
                    if (isLast) onFinished() else pageIndex += 1
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 20.dp)
                    .height(48.dp),
                shape = CircleShape
            ) {
                Text(
                    if (isLast) "Get Started" else "Continue",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
private fun GlassCircleButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f))
            .border(0.6.dp, Color.White.copy(alpha = 0.22f), CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            icon,
            contentDescription = contentDescription,
            tint = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.size(22.dp)
        )
    }
}
