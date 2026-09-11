// RaTeXTextAttachment.swift — NSTextAttachment that renders a LaTeX formula inline with text.
//
// The attachment uses a custom cell (macOS) or a pre-rendered image (iOS) so
// that the formula's baseline aligns with the surrounding text baseline.

#if os(macOS)
import AppKit

private final class RaTeXTextAttachmentCell: NSTextAttachmentCell {
    private let renderer: RaTeXRenderer
    private let formulaDepth: CGFloat

    init(renderer: RaTeXRenderer) {
        self.renderer = renderer
        self.formulaDepth = renderer.depth
        super.init(imageCell: NSImage(size: .zero))
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func cellSize() -> NSSize {
        NSSize(width: renderer.width, height: renderer.totalHeight)
    }

    override func cellBaselineOffset() -> NSPoint {
        // Offset from the text baseline to the cell's drawing origin.
        // In AppKit's y-up text coordinate system a negative y moves the
        // cell below the baseline, letting the formula extend `depth` points
        // beneath it — so the formula's internal baseline aligns with the
        // surrounding text baseline.
        NSPoint(x: 0, y: -formulaDepth)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }

        let contentW = renderer.width
        let contentH = renderer.totalHeight
        var drawScale: CGFloat = 1
        if contentW > 0, contentH > 0 {
            let sx = cellFrame.width / contentW
            let sy = cellFrame.height / contentH
            drawScale = min(1, min(sx, sy))
        }

        let drawW = contentW * drawScale
        let drawX = cellFrame.minX + max(0, (cellFrame.width - drawW) / 2)
        let drawY = cellFrame.minY

        ctx.translateBy(x: drawX, y: drawY)
        ctx.scaleBy(x: drawScale, y: drawScale)

        renderer.draw(in: ctx)
    }

    override func draw(
        withFrame cellFrame: NSRect,
        in controlView: NSView?,
        characterIndex charIndex: Int,
        layoutManager: NSLayoutManager
    ) {
        draw(withFrame: cellFrame, in: controlView)
    }
}
#else
import UIKit
#endif

@MainActor
class RaTeXTextAttachment: NSTextAttachment {

    init(renderer: RaTeXRenderer) {
        super.init(data: nil, ofType: nil)

        let size = CGSize(width: renderer.width, height: renderer.totalHeight)
        guard size.width > 0, size.height > 0 else { return }

        #if os(macOS)
        // Let the cell handle sizing / baseline / drawing (vector quality).
        // bounds.origin.y is left at 0 — all positioning is via cellBaselineOffset().
        self.bounds = CGRect(origin: .zero, size: size)
        attachmentCell = RaTeXTextAttachmentCell(renderer: renderer)
        #else
        // Snap the bitmap to the pixel grid. The layout gives fractional sizes and a fractional
        // depth; a bitmap drawn at a fractional size and placed at a fractional baseline offset is
        // resampled when TextKit composites it, which softens every edge (measured: fewer fully
        // black pixels and more mid-grays than the same glyphs drawn by WebKit).
        let scale = UIScreen.main.scale
        let snapUp = { (v: CGFloat) in ceil(v * scale) / scale }
        let snap = { (v: CGFloat) in (v * scale).rounded() / scale }
        let bitmapSize = CGSize(width: snapUp(size.width), height: snapUp(size.height))

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let imageRenderer = UIGraphicsImageRenderer(size: bitmapSize, format: format)
        self.image = imageRenderer.image { ctx in
            renderer.draw(in: ctx.cgContext)
        }

        // origin.y = -depth shifts the image down so the formula baseline
        // (at `height` from the top) aligns with the text baseline.
        self.bounds = CGRect(x: 0, y: -snap(renderer.depth), width: bitmapSize.width, height: bitmapSize.height)
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
}
