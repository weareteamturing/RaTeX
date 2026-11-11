// RaTeXInlineLayout.kt — Builds and lays out the text behind RaTeXInlineView.
//
// RaTeXInlineView draws the layout on the main thread. RaTeXInlineViewManager.measure lays the
// same text out on Fabric's layout thread so Yoga gets the height before the view is mounted.
// Both build the spannable with `buildSpannable` and the StaticLayout with `buildLayout`, so the
// height Yoga reserves is the height the view draws.
//
// Nothing here needs the main thread: formula parsing is thread-safe and the typeface cache is a
// ConcurrentHashMap.

package io.ratex

import android.content.Context
import android.content.res.AssetManager
import android.graphics.Canvas
import android.graphics.Typeface
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import androidx.annotation.ColorInt
import com.facebook.react.common.assets.ReactFontManager
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.ceil
import kotlin.math.roundToInt

/** Inputs that decide the size of an inline string. Colors do not change the size. */
internal data class RaTeXInlineTextStyle(
    val formulaFontSize: Float = 16f,
    val textFontSize: Float = 16f,
    /** Already trimmed; null means the default typeface. */
    val textFontFamily: String? = null,
    /** Baseline-to-baseline distance in dp (CSS `line-height`); 0 keeps the natural spacing. */
    val textLineHeight: Float = 0f,
    val textItalic: Boolean = false,
    val textUnderline: Boolean = false,
    val textLineThrough: Boolean = false,
)

internal object RaTeXInlineLayout {

    // MARK: - Spannable

    /**
     * Text with each `$...$` formula replaced by a [RaTeXFormulaSpan]. A formula that does not
     * parse is kept as literal `$latex$` text. Blocking (parses every formula); call it off the
     * main thread.
     */
    fun buildSpannable(
        content: String,
        formulaFontSizeDp: Float,
        @ColorInt formulaColor: Int,
        density: Float,
        typefaceLoader: ((String) -> Typeface?)?,
    ): SpannableStringBuilder {
        val builder = SpannableStringBuilder()
        val formulaFontSizePx = formulaFontSizeDp * density
        for (segment in parseContent(content)) {
            when (segment) {
                is Segment.Text -> builder.append(segment.content)
                is Segment.Formula -> {
                    val renderer = try {
                        val dl = RaTeXEngine.parseBlocking(
                            segment.content,
                            displayMode = false,
                            color = formulaColor,
                        )
                        RaTeXRenderer(dl, formulaFontSizePx, typefaceLoader)
                    } catch (_: Exception) {
                        null
                    }
                    if (renderer != null && renderer.widthPx > 0) {
                        val start = builder.length
                        builder.append("￼")
                        builder.setSpan(
                            RaTeXFormulaSpan(renderer),
                            start, builder.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                    } else {
                        builder.append("\$${segment.content}\$")
                    }
                }
            }
        }
        return builder
    }

    // MARK: - Paint and layout

    fun applyTextPaint(
        paint: TextPaint,
        context: Context,
        style: RaTeXInlineTextStyle,
        @ColorInt textColor: Int,
        density: Float,
    ) {
        paint.textSize = style.textFontSize * density
        paint.color = textColor
        val typefaceStyle = if (style.textItalic) Typeface.ITALIC else Typeface.NORMAL
        paint.typeface = resolveTextTypeface(context, style.textFontFamily, typefaceStyle)
        paint.isUnderlineText = style.textUnderline
        paint.isStrikeThruText = style.textLineThrough
    }

    /** Width the text wants on one line, in px. */
    fun desiredWidthPx(spannable: CharSequence, paint: TextPaint): Int =
        ceil(Layout.getDesiredWidth(spannable, paint)).toInt().coerceAtLeast(1)

    fun buildLayout(
        spannable: CharSequence,
        paint: TextPaint,
        widthPx: Int,
        style: RaTeXInlineTextStyle,
        density: Float,
    ): RaTeXInlineTextLayout {
        val minLineHeightPx =
            if (style.textLineHeight > 0f) (style.textLineHeight * density).roundToInt() else 0
        val layout = StaticLayout.Builder
            .obtain(spannable, 0, spannable.length, paint, widthPx.coerceAtLeast(1))
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            // With a line height the line box is ascent..descent grown to that height, as on iOS;
            // the font's top/bottom overshoot padding would make the first and last line taller.
            .setIncludePad(minLineHeightPx == 0)
            .build()
        return RaTeXInlineTextLayout(layout, minLineHeightPx)
    }

    /** The longest line, in px — iOS reports usedRect.width, the same quantity. */
    fun usedWidthPx(layout: RaTeXInlineTextLayout): Int {
        var max = 0f
        for (i in 0 until layout.layout.lineCount) {
            max = maxOf(max, layout.layout.getLineWidth(i))
        }
        return ceil(max.toDouble()).toInt()
    }

    // MARK: - Typeface

    private val TEXT_FONT_ASSET_DIRS = listOf("font", "fonts")
    private val TEXT_FONT_FILE_EXTENSIONS = listOf(".ttf", ".otf")
    // Indices map to Android Typeface style constants: NORMAL=0, BOLD=1, ITALIC=2, BOLD_ITALIC=3.
    private val TEXT_FONT_STYLE_SUFFIXES = listOf("", "_bold", "_italic", "_bold_italic")
    private val textTypefaceCache = ConcurrentHashMap<String, Typeface>()
    private val NON_FONT_ASSET_CHARS = Regex("[^a-z0-9]+")

    private data class TextFontAssetCandidate(
        val baseName: String,
        val exactStyle: Boolean,
    )

    fun resolveTextTypeface(context: Context, family: String?, style: Int): Typeface {
        if (family == null) return Typeface.defaultFromStyle(style)
        loadTextTypefaceFromAssets(context.assets, family, style)?.let { return it }
        // ReactFontManager handles runtime-registered fonts (e.g. expo-font) and
        // falls back to Typeface.create() internally — it does not throw.
        return ReactFontManager.getInstance().getTypeface(family, style, context.assets)
    }

    private fun loadTextTypefaceFromAssets(
        assetManager: AssetManager,
        family: String,
        style: Int,
    ): Typeface? {
        val cacheKey = "$family:$style"
        textTypefaceCache[cacheKey]?.let { return it }

        val candidates = textFontAssetCandidates(family, style)
        for (dir in TEXT_FONT_ASSET_DIRS) {
            for (candidate in candidates) {
                for (extension in TEXT_FONT_FILE_EXTENSIONS) {
                    val path = "$dir/${candidate.baseName}$extension"
                    loadTypefaceFromAssetPath(assetManager, path, style, candidate.exactStyle)?.let {
                        textTypefaceCache[cacheKey] = it
                        return it
                    }
                }
            }
        }

        for (dir in TEXT_FONT_ASSET_DIRS) {
            val files = try {
                assetManager.list(dir)?.toList().orEmpty()
            } catch (_: Exception) {
                emptyList()
            }
            if (files.isEmpty()) continue

            for (candidate in candidates) {
                val normalizedCandidate = normalizeFontAssetName(candidate.baseName)
                val compactCandidate = compactFontAssetName(candidate.baseName)
                val file = files.firstOrNull { assetName ->
                    val extension = TEXT_FONT_FILE_EXTENSIONS.firstOrNull {
                        assetName.endsWith(it, ignoreCase = true)
                    }
                    if (extension == null) {
                        false
                    } else {
                        val assetBaseName = assetName.dropLast(extension.length)
                        assetBaseName.equals(candidate.baseName, ignoreCase = true) ||
                            (normalizedCandidate.isNotEmpty() &&
                                normalizeFontAssetName(assetBaseName) == normalizedCandidate) ||
                            (compactCandidate.isNotEmpty() &&
                                compactFontAssetName(assetBaseName) == compactCandidate)
                    }
                } ?: continue

                loadTypefaceFromAssetPath(assetManager, "$dir/$file", style, candidate.exactStyle)?.let {
                    textTypefaceCache[cacheKey] = it
                    return it
                }
            }
        }
        return null
    }

    private fun loadTypefaceFromAssetPath(
        assetManager: AssetManager,
        path: String,
        style: Int,
        exactStyle: Boolean,
    ): Typeface? = try {
        val typeface = Typeface.createFromAsset(assetManager, path)
        if (exactStyle || style == Typeface.NORMAL) {
            typeface
        } else {
            Typeface.create(typeface, style)
        }
    } catch (_: RuntimeException) {
        null
    }

    private fun textFontAssetCandidates(
        family: String,
        style: Int,
    ): List<TextFontAssetCandidate> {
        val suffix = TEXT_FONT_STYLE_SUFFIXES.getOrElse(style) { "" }
        val baseNames = textFontBaseNameVariants(family)
        val candidates = mutableListOf<TextFontAssetCandidate>()
        if (suffix.isNotEmpty()) {
            baseNames.forEach { candidates += TextFontAssetCandidate("$it$suffix", true) }
        }
        baseNames.forEach { candidates += TextFontAssetCandidate(it, suffix.isEmpty()) }
        return candidates.distinctBy { "${it.baseName}:${it.exactStyle}" }
    }

    private fun textFontBaseNameVariants(family: String): List<String> {
        val trimmed = family.trim()
        val underscored = trimmed.replace('-', '_').replace(' ', '_')
        val androidResourceName = normalizeFontAssetName(trimmed)
        return listOf(trimmed, underscored, androidResourceName)
            .filter { it.isNotEmpty() }
            .distinct()
    }

    private fun normalizeFontAssetName(value: String): String =
        NON_FONT_ASSET_CHARS
            .replace(value.trim().lowercase(Locale.US), "_")
            .trim('_')

    private fun compactFontAssetName(value: String): String =
        NON_FONT_ASSET_CHARS.replace(value.trim().lowercase(Locale.US), "")

    // MARK: - Parsing

    sealed class Segment {
        data class Text(val content: String) : Segment()
        data class Formula(val content: String) : Segment()
    }

    fun parseContent(content: String): List<Segment> {
        val segments = mutableListOf<Segment>()
        val current = StringBuilder()
        var inFormula = false
        var index = 0

        while (index < content.length) {
            val ch = content[index]
            if (ch == '\\' && index + 1 < content.length && content[index + 1] == '$') {
                if (inFormula) {
                    current.append("\\$")
                } else {
                    current.append('$')
                }
                index += 2
                continue
            }

            if (ch == '$') {
                if (inFormula) {
                    if (current.isNotEmpty()) {
                        segments.add(Segment.Formula(current.toString()))
                    } else {
                        segments.add(Segment.Text("\$\$"))
                    }
                    current.clear()
                    inFormula = false
                } else {
                    if (current.isNotEmpty()) {
                        segments.add(Segment.Text(current.toString()))
                    }
                    current.clear()
                    inFormula = true
                }
            } else {
                current.append(ch)
            }
            index += 1
        }

        if (inFormula) {
            segments.add(Segment.Text("\$$current"))
        } else if (current.isNotEmpty()) {
            segments.add(Segment.Text(current.toString()))
        }

        return segments
    }
}

/**
 * A StaticLayout plus CSS line-height applied as a minimum per line, like the iOS paragraph
 * style (minimumLineHeight): a line shorter than [minLineHeightPx] grows to it, a line made
 * taller by a formula keeps its height. The extra space goes above the line, where TextKit puts
 * it, so both platforms place each baseline at the same height.
 *
 * Why not StaticLayout features: line spacing (setLineSpacing) is added between lines only, so a
 * single line stayed at the font's natural height (20.2dp instead of 24dp for 15dp text). A
 * LineHeightSpan hits AOSP StaticLayout.generate (checked in the API 33 source): after out() lets
 * the span rewrite a line's font metrics, generate() keeps those rewritten metrics as the
 * "current span" metrics for the next line of the same style run, so every line after a tall
 * formula got the formula's height. Measured: a 3-line block with \dfrac on line 1 came out
 * 85.7dp instead of 70dp.
 */
internal class RaTeXInlineTextLayout(
    val layout: StaticLayout,
    private val minLineHeightPx: Int,
) {
    /** Vertical shift of each line: the extra space of that line and of every line above it. */
    private val lineShift = IntArray(layout.lineCount)

    /** Total height in px. */
    val height: Int

    init {
        var shift = 0
        for (i in 0 until layout.lineCount) {
            val natural = layout.getLineBottom(i) - layout.getLineTop(i)
            shift += (minLineHeightPx - natural).coerceAtLeast(0)
            lineShift[i] = shift
        }
        height = layout.height + shift
    }

    private companion object {
        const val BLEED = 10_000f
    }

    fun draw(canvas: Canvas) {
        if (lineShift.isEmpty() || lineShift.last() == 0) {
            layout.draw(canvas)
            return
        }
        // StaticLayout draws every line at a fixed position. Draw it once per line, shifted down
        // and clipped to that line; inline text is a few lines, so the repeated pass is cheap.
        val last = layout.lineCount - 1
        for (i in 0..last) {
            canvas.save()
            canvas.translate(0f, lineShift[i].toFloat())
            // Clip to this line's own box. Opening the clip into the extra space above would
            // let the previous line, drawn there by the same pass, show its bottom edge (seen
            // on the emulator as glyph fragments under each line). The first and last line
            // are open towards the view's edges.
            canvas.clipRect(
                -BLEED,
                if (i == 0) -BLEED else layout.getLineTop(i).toFloat(),
                maxOf(layout.width.toFloat(), layout.getLineWidth(i)) + BLEED,
                if (i == last) layout.getLineBottom(i) + BLEED else layout.getLineBottom(i).toFloat(),
            )
            layout.draw(canvas)
            canvas.restore()
        }
    }
}
