// RaTeXView.swift — Platform view and SwiftUI wrapper for rendering a LaTeX formula.

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

// MARK: - UIKit / AppKit

/// A view that renders a LaTeX formula using the RaTeX engine.
///
/// ```swift
/// let view = RaTeXView()
/// view.latex = #"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#
/// view.fontSize = 28
/// ```
@MainActor
public class RaTeXView: PlatformView {

    // MARK: Public properties

    /// The LaTeX math-mode string to render.
    public var latex: String = "" {
        didSet { guard latex != oldValue else { return }; rerender() }
    }

    /// Font size in points. Determines the physical size of the formula.
    public var fontSize: CGFloat = 24 {
        didSet { guard fontSize != oldValue else { return }; rerender() }
    }

    /// Rendering mode. `true` (default) for display/block style (`$$...$$`);
    /// `false` for inline/text style (`$...$`).
    public var displayMode: Bool = true {
        didSet { guard displayMode != oldValue else { return }; rerender() }
    }

    /// Default formula color. Explicit LaTeX colors still take precedence.
    public var color: PlatformColor = .black {
        didSet { guard !color.isEqual(oldValue) else { return }; rerender() }
    }

    /// Called when a render error occurs (e.g. invalid LaTeX).
    public var onError: ((Error) -> Void)?

    /// The error from the most recent render, or nil if it succeeded. Lets a host that attaches
    /// its listener after the render (React Native Fabric mounts props before the event emitter)
    /// still learn that the view is showing nothing because the input failed to parse.
    public private(set) var lastError: Error?

    // MARK: Private state

    private var renderer: RaTeXRenderer?

    // MARK: Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(macOS)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor
        #else
        backgroundColor = .clear
        contentMode = .redraw
        #endif
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        #if os(macOS)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor
        #else
        backgroundColor = .clear
        contentMode = .redraw
        #endif
    }

    #if os(macOS)
    public override var isFlipped: Bool { true }

    /// Equivalent to iOS `contentMode = .redraw`: when the frame size changes (e.g.
    /// Fabric sets the frame after updateProps already triggered a display update),
    /// mark the view dirty so `draw(_:)` is called again with the new bounds.
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if renderer != nil {
            platformSetNeedsDisplay()
        }
    }
    #endif

    // MARK: Layout

    public override var intrinsicContentSize: CGSize {
        guard let r = renderer else { return .zero }
        return CGSize(width: r.width, height: r.totalHeight)
    }

    // MARK: Drawing

    public override func draw(_ rect: CGRect) {
        #if os(macOS)
        guard let renderer, let ctx = NSGraphicsContext.current?.cgContext else { return }
        #else
        guard let renderer, let ctx = UIGraphicsGetCurrentContext() else { return }
        #endif

        let contentW = renderer.width
        let contentH = renderer.totalHeight
        let availW = max(0, bounds.width)
        let availH = max(0, bounds.height)

        ctx.saveGState()
        ctx.clip(to: bounds)

        // Scale down to fit in the assigned layout size; never scale up.
        let sx: CGFloat = contentW > 0 ? (availW / contentW) : 1
        let sy: CGFloat = contentH > 0 ? (availH / contentH) : 1
        let scale = min(1, min(sx, sy))

        let scaledW = contentW * scale
        let scaledH = contentH * scale
        let dx = max(0, (availW - scaledW) / 2)
        let dy = max(0, (availH - scaledH) / 2)

        ctx.translateBy(x: dx, y: dy)
        ctx.scaleBy(x: scale, y: scale)
        renderer.draw(in: ctx)
        ctx.restoreGState()
    }

    #if os(macOS)
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rerender()
    }
    #else
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard let previousTraitCollection else { return }
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }
        rerender()
    }
    #endif

    // MARK: Private

    private func rerender() {
        RaTeXFontLoader.ensureLoaded()
        do {
            #if os(macOS)
            let dl = try RaTeXEngine.shared.parse(
                latex,
                displayMode: displayMode,
                color: color,
                appearance: effectiveAppearance
            )
            #else
            let dl = try RaTeXEngine.shared.parse(
                latex,
                displayMode: displayMode,
                color: color,
                traitCollection: traitCollection
            )
            #endif
            renderer = RaTeXRenderer(displayList: dl, fontSize: fontSize)
            lastError = nil
            invalidateIntrinsicContentSize()
            platformSetNeedsDisplay()
        } catch {
            // Drop the previous formula. Keeping it left the old drawing on screen and kept
            // reporting its size, so a view reused for an unparsable input showed the formula
            // it had rendered before.
            renderer = nil
            lastError = error
            invalidateIntrinsicContentSize()
            platformSetNeedsDisplay()
            onError?(error)
        }
    }
}

// MARK: - SwiftUI

#if os(macOS)

/// A SwiftUI view that renders a LaTeX formula.
///
/// ```swift
/// RaTeXFormula(latex: #"\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}"#, fontSize: 24)
/// ```
@available(macOS 11, *)
public struct RaTeXFormula: NSViewRepresentable {
    public let latex: String
    public var fontSize: CGFloat = 24
    public var onError: ((Error) -> Void)? = nil

    public init(latex: String, fontSize: CGFloat = 24, onError: ((Error) -> Void)? = nil) {
        self.latex = latex
        self.fontSize = fontSize
        self.onError = onError
    }

    public func makeNSView(context: Context) -> RaTeXView {
        let view = RaTeXView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    public func updateNSView(_ nsView: RaTeXView, context: Context) {
        nsView.fontSize = fontSize
        nsView.onError  = onError
        nsView.latex    = latex
    }
}

#else

/// A SwiftUI view that renders a LaTeX formula.
///
/// ```swift
/// RaTeXFormula(latex: #"\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}"#, fontSize: 24)
/// ```
@available(iOS 14, *)
public struct RaTeXFormula: UIViewRepresentable {
    public let latex: String
    public var fontSize: CGFloat = 24
    public var onError: ((Error) -> Void)? = nil

    public init(latex: String, fontSize: CGFloat = 24, onError: ((Error) -> Void)? = nil) {
        self.latex = latex
        self.fontSize = fontSize
        self.onError = onError
    }

    public func makeUIView(context: Context) -> RaTeXView {
        let view = RaTeXView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    public func updateUIView(_ uiView: RaTeXView, context: Context) {
        uiView.fontSize = fontSize
        uiView.onError  = onError
        uiView.latex    = latex
    }
}

#endif
