// RaTeXUnicodeFont.kt — lets the host app choose the font RaTeX uses for glyphs
// outside the KaTeX fonts (CJK text inside $…$, for example).

package io.ratex

import android.content.Context
import android.content.pm.PackageManager
import android.system.Os
import android.util.Log
import java.io.File

/**
 * The Rust core falls back to a *system sans* font for any character the KaTeX fonts
 * lack, and reads `RATEX_UNICODE_FONT` (a file path) as the highest-priority override.
 * The result is cached on first use, so the variable must be set before the first render.
 *
 * Declare the font in the app manifest as an asset path:
 *
 * ```xml
 * <application>
 *   <meta-data android:name="io.ratex.UNICODE_FONT" android:value="fonts/NotoSerifKR-Regular.otf" />
 * </application>
 * ```
 *
 * Assets have no file path, so the file is copied once into `filesDir/ratex/`.
 */
object RaTeXUnicodeFont {
    private const val TAG = "RaTeXUnicodeFont"
    private const val META_KEY = "io.ratex.UNICODE_FONT"
    private const val ENV_KEY = "RATEX_UNICODE_FONT"

    @Volatile private var configured = false

    @JvmStatic
    fun configureFromManifest(context: Context) {
        if (configured) return
        configured = true
        val assetPath = readMeta(context) ?: return
        try {
            val target = File(File(context.filesDir, "ratex"), File(assetPath).name)
            val size = context.assets.openFd(assetPath).use { it.length }
            if (!target.exists() || target.length() != size) {
                target.parentFile?.mkdirs()
                context.assets.open(assetPath).use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
            }
            Os.setenv(ENV_KEY, target.absolutePath, true)
        } catch (e: Exception) {
            Log.w(TAG, "could not configure $ENV_KEY from asset '$assetPath'", e)
        }
    }

    private fun readMeta(context: Context): String? = try {
        val info = context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
        info.metaData?.getString(META_KEY)?.takeIf { it.isNotBlank() }
    } catch (e: PackageManager.NameNotFoundException) {
        null
    }
}
