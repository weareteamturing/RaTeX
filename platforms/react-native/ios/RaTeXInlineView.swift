// RaTeXInlineView.swift — Platform view that renders a mix of plain text and $...$
// LaTeX formulas in a single text flow using NSLayoutManager.
//
// Each formula is converted to an image-backed NSTextAttachment with baseline-
// aligned bounds, so TextKit handles word-wrapping and line-breaking at character
// granularity — the same way a native label or text view would.

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
public class RaTeXInlineView: PlatformView {

    // MARK: - Public properties

    public var content: String = "" {
        didSet { guard content != oldValue else { return }; rebuild() }
    }

    public var formulaFontSize: CGFloat = 16 {
        didSet { guard formulaFontSize != oldValue else { return }; rebuild() }
    }

    public var formulaColor: PlatformColor = .black {
        didSet { guard !formulaColor.isEqual(oldValue) else { return }; rebuild() }
    }

    public var textColor: PlatformColor = .black {
        didSet { guard !textColor.isEqual(oldValue) else { return }; rebuild() }
    }

    public var textFontSize: CGFloat = 16 {
        didSet { guard textFontSize != oldValue else { return }; rebuild() }
    }

    public var textFontFamily: String? {
        didSet {
            let newTrimmed = textFontFamily?.trimmingCharacters(in: .whitespacesAndNewlines)
            let oldTrimmed = trimmedTextFontFamily
            guard oldTrimmed != newTrimmed else { return }
            trimmedTextFontFamily = newTrimmed
            rebuild()
        }
    }

    /// Baseline-to-baseline distance in points, matching CSS `line-height`.
    /// 0 keeps the font's natural spacing.
    public var textLineHeight: CGFloat = 0 {
        didSet { guard textLineHeight != oldValue else { return }; rebuild() }
    }

    public var textItalic: Bool = false {
        didSet { guard textItalic != oldValue else { return }; rebuild() }
    }

    public var textUnderline: Bool = false {
        didSet { guard textUnderline != oldValue else { return }; rebuild() }
    }

    public var textLineThrough: Bool = false {
        didSet { guard textLineThrough != oldValue else { return }; rebuild() }
    }

    public var onContentSizeChange: ((CGFloat, CGFloat) -> Void)?

    // MARK: - Private state

    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer()
    private var lastReportedSize: CGSize = .zero
    private var lastEmittedSize: CGSize?
    private var lastLayoutWidth: CGFloat = -1
    private var trimmedTextFontFamily: String?

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        #if os(macOS)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        #else
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        #endif
        RaTeXInlineLayout.configure(textContainer)
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
    }

    #if os(macOS)
    public override var isFlipped: Bool { true }
    #endif

    // MARK: - Layout

    #if os(macOS)
    public override func layout() {
        super.layout()
        performLayoutPass()
    }
    #else
    public override func layoutSubviews() {
        super.layoutSubviews()
        performLayoutPass()
    }
    #endif

    private func performLayoutPass() {
        let w = bounds.width
        guard w > 0 else { return }
        if w != lastLayoutWidth {
            lastLayoutWidth = w
            textContainer.size = CGSize(width: w, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            reportContentSizeIfNeeded()
            platformSetNeedsDisplay()
        }
    }

    // MARK: - Drawing

    public override func draw(_ rect: CGRect) {
        guard textStorage.length > 0 else { return }
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
    }

    // MARK: - Intrinsic content size

    public override var intrinsicContentSize: CGSize {
        lastReportedSize
    }

    // MARK: - Content size

    private func reportContentSizeIfNeeded() {
        let size = textStorage.length > 0
            ? RaTeXInlineLayout.usedSize(layoutManager, textContainer)
            : .zero
        updateContentSize(size)
    }

    private func updateContentSize(_ size: CGSize) {
        let shouldInvalidateIntrinsicSize = size != lastReportedSize
        lastReportedSize = size
        if shouldInvalidateIntrinsicSize {
            invalidateIntrinsicContentSize()
        }
        guard size != lastEmittedSize else { return }
        lastEmittedSize = size
        onContentSizeChange?(size.width, size.height)
    }

    public func resetContentSizeReporting() {
        lastEmittedSize = nil
        lastLayoutWidth = -1
        platformSetNeedsLayout()
    }

    // MARK: - Rebuild

    private func rebuild() {
        RaTeXFontLoader.ensureLoaded()
        let attributed = buildAttributedString()
        textStorage.setAttributedString(attributed)
        lastLayoutWidth = -1
        lastEmittedSize = nil

        // Compute single-line size so intrinsicContentSize is non-zero before
        // the first layout pass (prevents zero-width collapse when the
        // parent uses alignItems: 'center').
        if textStorage.length > 0 {
            textContainer.size = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: .greatestFiniteMagnitude
            )
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            lastReportedSize = CGSize(
                width: max(0, ceil(usedRect.width)),
                height: max(0, ceil(usedRect.height))
            )
        } else {
            lastReportedSize = .zero
        }

        invalidateIntrinsicContentSize()
        platformSetNeedsLayout()
        platformSetNeedsDisplay()
    }

    private func buildAttributedString() -> NSAttributedString {
        let style = RaTeXInlineTextStyle(
            formulaFontSize: formulaFontSize,
            textFontSize: textFontSize,
            textFontFamily: trimmedTextFontFamily,
            textLineHeight: textLineHeight,
            textItalic: textItalic,
            textUnderline: textUnderline,
            textLineThrough: textLineThrough
        )
        return RaTeXInlineLayout.attributedString(
            content: content,
            style: style,
            textColor: textColor
        ) { [self] latex in makeFormulaAttachment(latex) }
    }

    private func makeFormulaAttachment(_ latex: String) -> RaTeXTextAttachment? {
        do {
            #if os(macOS)
            let dl = try RaTeXEngine.shared.parse(
                latex,
                displayMode: false,
                color: formulaColor,
                appearance: effectiveAppearance
            )
            #else
            let dl = try RaTeXEngine.shared.parse(
                latex,
                displayMode: false,
                color: formulaColor,
                traitCollection: traitCollection
            )
            #endif
            let renderer = RaTeXRenderer(displayList: dl, fontSize: formulaFontSize)
            return RaTeXTextAttachment(renderer: renderer)
        } catch {
            return nil
        }
    }

    // MARK: - Appearance changes

    #if os(macOS)
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuild()
    }
    #else
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard let previousTraitCollection else { return }
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }
        rebuild()
    }
    #endif
}
