// RaTeXInlineViewManager.kt (New Architecture) — Codegen-generated interface.

package io.ratex

import android.content.Context
import android.graphics.Color
import android.text.TextPaint
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.RaTeXInlineViewManagerDelegate
import com.facebook.react.viewmanagers.RaTeXInlineViewManagerInterface
import com.facebook.yoga.YogaMeasureMode
import com.facebook.yoga.YogaMeasureOutput

@ReactModule(name = RaTeXInlineViewManager.NAME)
class RaTeXInlineViewManager(private val reactContext: ReactApplicationContext) :
    SimpleViewManager<RaTeXInlineView>(),
    RaTeXInlineViewManagerInterface<RaTeXInlineView> {

    companion object {
        const val NAME = "RaTeXInlineView"
    }

    private val delegate = RaTeXInlineViewManagerDelegate(this)

    override fun getDelegate() = delegate

    override fun getName(): String = NAME

    override fun onAfterUpdateTransaction(view: RaTeXInlineView) {
        super.onAfterUpdateTransaction(view)
        view.commitProps()
    }

    override fun createViewInstance(ctx: ThemedReactContext): RaTeXInlineView {
        val view = RaTeXInlineView(ctx)
        view.onContentSizeChange = { width, height ->
            val dispatcher = UIManagerHelper.getEventDispatcherForReactTag(ctx, view.id)
            val surfaceId = UIManagerHelper.getSurfaceId(ctx)
            dispatcher?.dispatchEvent(
                RaTeXContentSizeEvent(surfaceId, view.id, width, height)
            )
        }
        return view
    }

    @ReactProp(name = "content")
    override fun setContent(view: RaTeXInlineView, value: String?) {
        view.content = value ?: ""
    }

    @ReactProp(name = "fontSize", defaultFloat = 16f)
    override fun setFontSize(view: RaTeXInlineView, value: Float) {
        view.formulaFontSize = value
    }

    @ReactProp(name = "color", customType = "Color")
    override fun setColor(view: RaTeXInlineView, value: Int?) {
        view.formulaColor = value ?: Color.BLACK
    }

    @ReactProp(name = "textColor", customType = "Color")
    override fun setTextColor(view: RaTeXInlineView, value: Int?) {
        view.inlineTextColor = value ?: Color.BLACK
    }

    @ReactProp(name = "textFontSize", defaultFloat = 16f)
    override fun setTextFontSize(view: RaTeXInlineView, value: Float) {
        view.textFontSize = value
    }

    @ReactProp(name = "textFontFamily")
    override fun setTextFontFamily(view: RaTeXInlineView, value: String?) {
        view.textFontFamily = value
    }

    @ReactProp(name = "textLineHeight", defaultFloat = 0f)
    override fun setTextLineHeight(view: RaTeXInlineView, value: Float) {
        view.textLineHeight = value
    }

    @ReactProp(name = "textItalic", defaultBoolean = false)
    override fun setTextItalic(view: RaTeXInlineView, value: Boolean) {
        view.textItalic = value
    }

    @ReactProp(name = "textUnderline", defaultBoolean = false)
    override fun setTextUnderline(view: RaTeXInlineView, value: Boolean) {
        view.textUnderline = value
    }

    @ReactProp(name = "textLineThrough", defaultBoolean = false)
    override fun setTextLineThrough(view: RaTeXInlineView, value: Boolean) {
        view.textLineThrough = value
    }

    // Synchronous measure for Fabric, called by the C++ shadow node's measureContent through
    // FabricUIManager.measure. Without it the view's height came only from JS — a one-line
    // estimate, then onContentSizeChange after the asynchronous native layout — so a line
    // growing as a chat message streams in shrank and grew back. Lays out the same text as
    // RaTeXInlineView (RaTeXInlineLayout); color does not change the size. `width` is in px
    // (FabricUIManager converts the constraint), the result in dp.
    override fun measure(
        context: Context,
        localData: ReadableMap?,
        props: ReadableMap?,
        state: ReadableMap?,
        width: Float,
        widthMode: YogaMeasureMode?,
        height: Float,
        heightMode: YogaMeasureMode?,
        attachmentsPositions: FloatArray?,
    ): Long {
        val content = props?.getString("content").orEmpty()
        if (content.isBlank()) {
            return YogaMeasureOutput.make(0f, 0f)
        }
        fun float(key: String): Float =
            if (props?.hasKey(key) == true) props.getDouble(key).toFloat() else 0f
        fun bool(key: String): Boolean =
            props?.hasKey(key) == true && props.getBoolean(key)
        // 0 means unset; the view's props default to 16 (see the @ReactProp setters).
        val fontSize = float("fontSize").takeIf { it > 0f } ?: 16f
        val style = RaTeXInlineTextStyle(
            formulaFontSize = fontSize,
            textFontSize = float("textFontSize").takeIf { it > 0f } ?: 16f,
            textFontFamily = props?.getString("textFontFamily")?.trim()?.takeIf { it.isNotEmpty() },
            textLineHeight = float("textLineHeight"),
            textItalic = bool("textItalic"),
            textUnderline = bool("textUnderline"),
            textLineThrough = bool("textLineThrough"),
        )
        return try {
            val density = context.resources.displayMetrics.density
            val spannable = RaTeXInlineLayout.buildSpannable(
                content,
                style.formulaFontSize,
                Color.BLACK,
                density,
                null,
            )
            val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG)
            RaTeXInlineLayout.applyTextPaint(paint, context, style, Color.BLACK, density)
            val desired = RaTeXInlineLayout.desiredWidthPx(spannable, paint)
            val layoutWidth = when {
                widthMode == YogaMeasureMode.EXACTLY -> width.toInt()
                widthMode == YogaMeasureMode.AT_MOST && width.isFinite() ->
                    minOf(desired, width.toInt())
                else -> desired
            }.coerceAtLeast(1)
            val layout = RaTeXInlineLayout.buildLayout(spannable, paint, layoutWidth, style, density)
            val usedWidth = when (widthMode) {
                YogaMeasureMode.EXACTLY -> layoutWidth
                // One px of slack: Yoga rounds the frame to the pixel grid and may hand the view
                // a pixel less than it measured, which would wrap the last word that just fit.
                else -> minOf(RaTeXInlineLayout.usedWidthPx(layout) + 1, layoutWidth)
            }
            YogaMeasureOutput.make(usedWidth / density, layout.height / density)
        } catch (e: Throwable) {
            YogaMeasureOutput.make(0f, 0f)
        }
    }
}
