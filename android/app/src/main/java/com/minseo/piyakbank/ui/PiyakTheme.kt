package com.minseo.piyakbank.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

internal val Sunflower = Color(0xFFFFD766)
internal val WarmInk = Color(0xFF382C29)
internal val Lavender = Color(0xFFECE4FA)
internal val Mint = Color(0xFFE0F2E8)
internal val Peach = Color(0xFFFFE8D6)

private val LightColors = lightColorScheme(
    primary = Color(0xFF725318), onPrimary = Color.White,
    primaryContainer = Sunflower, onPrimaryContainer = WarmInk,
    secondary = Color(0xFF5E5175), onSecondary = Color.White,
    secondaryContainer = Lavender, onSecondaryContainer = WarmInk,
    tertiary = Color(0xFF386348), tertiaryContainer = Mint, onTertiaryContainer = WarmInk,
    background = Color(0xFFFFFBF3), onBackground = WarmInk,
    surface = Color(0xFFFFFCF7), onSurface = WarmInk,
    surfaceVariant = Color(0xFFF3EDE3), onSurfaceVariant = Color(0xFF6F655E),
    outline = Color(0xFF897F74), outlineVariant = Color(0xFFE7DFD3),
    error = Color(0xFFAA3535), onError = Color.White,
)
private val DarkColors = darkColorScheme(
    primary = Sunflower, onPrimary = WarmInk,
    primaryContainer = Color(0xFF604715), onPrimaryContainer = Color(0xFFFFE7A8),
    secondary = Color(0xFFD3BEEA), onSecondary = Color(0xFF372B49),
    secondaryContainer = Color(0xFF45394F), onSecondaryContainer = Color(0xFFECE4FA),
    tertiary = Color(0xFFB3D9BD), tertiaryContainer = Color(0xFF294634),
    onTertiaryContainer = Mint,
    background = Color(0xFF211D1A), onBackground = Color(0xFFF4EDE4),
    surface = Color(0xFF2B2521), onSurface = Color(0xFFF4EDE4),
    surfaceVariant = Color(0xFF38302A), onSurfaceVariant = Color(0xFFD3C8BC),
    outline = Color(0xFFA69B8E), outlineVariant = Color(0xFF51473D),
)
private val RoundedType = Typography(
    displaySmall = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.ExtraBold, fontSize = 36.sp, lineHeight = 44.sp),
    headlineLarge = TextStyle(fontWeight = FontWeight.ExtraBold, fontSize = 30.sp, lineHeight = 39.sp),
    headlineMedium = TextStyle(fontWeight = FontWeight.Bold, fontSize = 26.sp, lineHeight = 34.sp),
    titleLarge = TextStyle(fontWeight = FontWeight.Bold, fontSize = 22.sp, lineHeight = 30.sp),
    titleMedium = TextStyle(fontWeight = FontWeight.Bold, fontSize = 17.sp, lineHeight = 25.sp),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 25.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 22.sp),
    bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 19.sp),
    labelLarge = TextStyle(fontWeight = FontWeight.Bold, fontSize = 14.sp, lineHeight = 21.sp),
)

@Composable
internal fun PiyakTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors, typography = RoundedType, content = content)
}
