// RaTeXInlineView.kt — Android View that renders text mixed with inline LaTeX formulas.
//
// Content is parsed for $...$ delimiters. Each formula is laid out via RaTeXEngine,
// wrapped in a RaTeXFormulaSpan (ReplacementSpan), and embedded in a SpannableString.
// Android's StaticLayout handles word-wrapping and line-breaking at character level.
// The spannable and the StaticLayout come from RaTeXInlineLayout, which the Fabric measure
// (RaTeXInlineViewManager.measure) uses too.

package io.ratex

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.TextPaint
import android.util.AttributeSet
import android.view.View
import androidx.annotation.ColorInt
import kotlin.math.max
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class RaTeXInlineView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0,
) : View(context, attrs, defStyle) {

    // MARK: - Public properties

    var content: String = ""
        set(value) {
            if (field == value) return
            field = value
            rebuild()
        }

    var formulaFontSize: Float = 16f
        set(value) {
            if (field == value) return
            field = value
            rebuild()
        }

    @ColorInt
    var formulaColor: Int = Color.BLACK
        set(value) {
            if (field == value) return
            field = value
            rebuild()
        }

    @ColorInt
    var inlineTextColor: Int = Color.BLACK
        set(value) {
            if (field == value) return
            field = value
            updateTextLayout()
        }

    var textFontSize: Float = 16f
        set(value) {
            if (field == value) return
            field = value
            updateTextLayout()
        }

    var textFontFamily: String? = null
        set(value) {
            val normalized = value?.trim()?.takeIf { it.isNotEmpty() }
            if (field == normalized) return
            field = normalized
            updateTextLayout()
        }

    /**
     * Baseline-to-baseline distance in points, matching CSS `line-height`.
     * 0 keeps the font's natural spacing.
     */
    var textLineHeight: Float = 0f
        set(value) {
            if (field == value) return
            field = value
            lastLayoutWidth = -1
            updateTextLayout()
        }

    var textItalic: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            updateTextLayout()
        }

    var textUnderline: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            updateTextLayout()
        }

    var textLineThrough: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            updateTextLayout()
        }

    var onContentSizeChange: ((width: Double, height: Double) -> Unit)? = null

    // MARK: - Private state

    private var currentSpannable: SpannableStringBuilder? = null
    private var staticLayout: RaTeXInlineTextLayout? = null
    private val textPaint = TextPaint(TextPaint.ANTI_ALIAS_FLAG)
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var buildJob: Job? = null
    private var lastReportedSize = Pair(0.0, 0.0)
    private var lastLayoutWidth = -1

    // MARK: - Measure

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val layout = ensureMeasuredLayout(widthMeasureSpec)
        val desiredWidth = max(
            (layout?.layout?.width ?: 0) + paddingLeft + paddingRight,
            suggestedMinimumWidth,
        )
        val desiredHeight = max(
            (layout?.height ?: 0) + paddingTop + paddingBottom,
            suggestedMinimumHeight,
        )
        setMeasuredDimension(
            resolveSize(desiredWidth, widthMeasureSpec),
            resolveSize(desiredHeight, heightMeasureSpec),
        )
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w != oldw) {
            rebuildLayout()
        }
    }

    // MARK: - Draw

    override fun onDraw(canvas: Canvas) {
        val layout = staticLayout ?: return
        canvas.save()
        canvas.translate(paddingLeft.toFloat(), paddingTop.toFloat())
        layout.draw(canvas)
        canvas.restore()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        buildJob?.cancel()
        buildJob = null
    }

    // MARK: - Private

    private fun currentStyle() = RaTeXInlineTextStyle(
        formulaFontSize = formulaFontSize,
        textFontSize = textFontSize,
        textFontFamily = textFontFamily,
        textLineHeight = textLineHeight,
        textItalic = textItalic,
        textUnderline = textUnderline,
        textLineThrough = textLineThrough,
    )

    private var rebuildPending = false

    /**
     * Props that change the spannable only mark it stale; [commitProps] rebuilds once. The view
     * managers call it from onAfterUpdateTransaction, after all props of an update are set, so
     * one update parses the formulas once instead of once per changed prop. The posted call
     * covers use outside a view manager.
     */
    private fun rebuild() {
        if (rebuildPending) return
        rebuildPending = true
        post { commitProps() }
    }

    fun commitProps() {
        if (!rebuildPending) return
        rebuildPending = false
        performRebuild()
    }

    private fun performRebuild() {
        buildJob?.cancel()
        if (content.isBlank()) {
            currentSpannable = null
            staticLayout = null
            lastLayoutWidth = -1
            reportContentSize(0.0, 0.0)
            requestLayout()
            invalidate()
            return
        }
        val content = content
        val formulaFontSize = formulaFontSize
        val formulaColor = formulaColor
        val density = context.resources.displayMetrics.density
        if (RaTeXFontLoader.isLoaded) {
            // Build in the same frame as the props update. Fabric has already laid the view out
            // at the height RaTeXInlineViewManager.measure computed for the new content; an
            // asynchronous build drew the previous text in that box for a frame.
            applySpannable(
                RaTeXInlineLayout.buildSpannable(content, formulaFontSize, formulaColor, density) {
                    RaTeXFontLoader.getTypeface(it)
                },
            )
            return
        }
        // First use: load the KaTeX fonts off the main thread.
        buildJob = scope.launch {
            val spannable = withContext(Dispatchers.Default) {
                RaTeXFontLoader.ensureLoaded(context)
                RaTeXInlineLayout.buildSpannable(
                    content,
                    formulaFontSize,
                    formulaColor,
                    density,
                ) { RaTeXFontLoader.getTypeface(it) }
            }
            applySpannable(spannable)
        }
    }

    private fun applySpannable(spannable: SpannableStringBuilder) {
        currentSpannable = spannable
        lastLayoutWidth = -1
        lastReportedSize = Pair(0.0, 0.0)
        rebuildLayout()
    }

    private fun rebuildLayout() {
        val spannable = currentSpannable ?: return
        val availWidth = width - paddingLeft - paddingRight
        if (availWidth <= 0) {
            requestLayout()
            invalidate()
            return
        }
        if (availWidth == lastLayoutWidth) return
        lastLayoutWidth = availWidth

        val density = context.resources.displayMetrics.density
        val style = currentStyle()
        RaTeXInlineLayout.applyTextPaint(textPaint, context, style, inlineTextColor, density)
        val layout = RaTeXInlineLayout.buildLayout(spannable, textPaint, availWidth, style, density)

        staticLayout = layout
        requestLayout()
        invalidate()

        reportContentSize(
            RaTeXInlineLayout.usedWidthPx(layout).toDouble() / density,
            layout.height.toDouble() / density,
        )
    }

    private fun ensureMeasuredLayout(widthMeasureSpec: Int): RaTeXInlineTextLayout? {
        val spannable = currentSpannable ?: return null
        val widthMode = MeasureSpec.getMode(widthMeasureSpec)
        val widthSize = MeasureSpec.getSize(widthMeasureSpec)
        val horizontalPadding = paddingLeft + paddingRight
        val density = context.resources.displayMetrics.density
        val style = currentStyle()
        RaTeXInlineLayout.applyTextPaint(textPaint, context, style, inlineTextColor, density)

        val targetWidth = when (widthMode) {
            MeasureSpec.EXACTLY -> (widthSize - horizontalPadding).coerceAtLeast(1)
            MeasureSpec.AT_MOST -> {
                val maxWidth = (widthSize - horizontalPadding).coerceAtLeast(1)
                minOf(RaTeXInlineLayout.desiredWidthPx(spannable, textPaint), maxWidth)
            }
            else -> RaTeXInlineLayout.desiredWidthPx(spannable, textPaint)
        }

        val cachedLayout = staticLayout
        if (cachedLayout != null && lastLayoutWidth == targetWidth) {
            return cachedLayout
        }

        val measuredLayout =
            RaTeXInlineLayout.buildLayout(spannable, textPaint, targetWidth, style, density)

        staticLayout = measuredLayout
        lastLayoutWidth = targetWidth

        reportContentSize(
            RaTeXInlineLayout.usedWidthPx(measuredLayout).toDouble() / density,
            measuredLayout.height.toDouble() / density,
        )
        return measuredLayout
    }

    private var pendingReport: Pair<Double, Double>? = null

    /**
     * The size is sent after the current mount transaction, not from inside it. Fabric sets
     * the props before it applies the new frame, so a layout made while the props are applied
     * uses the old width; reporting it right away sent a transient size (measured: 72dp for a
     * one-line string laid out at the previous, narrower width) before the real one.
     */
    private fun reportContentSize(widthDp: Double, heightDp: Double) {
        val first = pendingReport == null
        pendingReport = Pair(widthDp, heightDp)
        if (first) post { flushContentSize() }
    }

    private fun flushContentSize() {
        val size = pendingReport ?: return
        pendingReport = null
        if (size != lastReportedSize) {
            lastReportedSize = size
            onContentSizeChange?.invoke(size.first, size.second)
        }
    }

    private fun updateTextLayout() {
        lastLayoutWidth = -1
        if (currentSpannable == null) return
        rebuildLayout()
    }
}
