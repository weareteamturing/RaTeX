// RaTeXInlineLayout.swift — Builds and measures the attributed string behind RaTeXInlineView.
//
// RaTeXInlineView draws the string on the main thread. RaTeXInlineMeasure measures it on
// Fabric's layout thread so Yoga gets the height before the view is mounted. Both build the
// string with `attributedString(...)` and lay it out with the same TextKit settings, so the
// height Yoga reserves is the height the view draws.
//
// Nothing here touches the main actor: no UIScreen, no image rendering, and the font-name
// cache is guarded by a lock.

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Inputs that decide the size of an inline string. Colors do not change the size and are
/// passed separately.
struct RaTeXInlineTextStyle {
    var formulaFontSize: CGFloat = 16
    var textFontSize: CGFloat = 16
    /// Already trimmed; nil or empty means the system font.
    var textFontFamily: String?
    /// Baseline-to-baseline distance in points (CSS `line-height`); 0 keeps the natural spacing.
    var textLineHeight: CGFloat = 0
    var textItalic = false
    var textUnderline = false
    var textLineThrough = false
}

enum RaTeXInlineLayout {

    // MARK: - Attributed string

    /// `formula` returns the attachment for one `$...$` segment, or nil when the LaTeX does not
    /// parse; the segment is then shown as literal `$latex$` text.
    static func attributedString(
        content: String,
        style: RaTeXInlineTextStyle,
        textColor: PlatformColor,
        formula: (String) -> NSTextAttachment?
    ) -> NSAttributedString {
        let segments = parseContent(content)
        let result = NSMutableAttributedString()

        let textFont = makeTextFont(style)
        var textAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor,
        ]
        if style.textUnderline {
            textAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.textLineThrough {
            textAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        for segment in segments {
            switch segment {
            case .text(let str):
                result.append(NSAttributedString(string: str, attributes: textAttrs))
            case .formula(let latex):
                if let attachment = formula(latex) {
                    result.append(NSAttributedString(attachment: attachment))
                } else {
                    result.append(NSAttributedString(string: "$\(latex)$", attributes: textAttrs))
                }
            }
        }

        if style.textLineHeight > 0 {
            // CSS line-height 처럼 줄의 최소 높이만 정한다. 최대는 두지 않는다 —
            // 분수처럼 높은 수식이 있는 줄은 CSS 도 줄 상자를 키우지 자르지 않는다.
            // 폰트 자연 행간보다 클 때만 적용한다.
            //
            // 문단 스타일은 문단 첫 글자의 것을 쓴다. 텍스트 런에만 붙이면
            // 수식으로 시작하는 문단("$a$\n$b$")은 스타일이 없어 자연 행간으로 돌아간다(실측).
            // 그래서 텍스트·첨부를 가리지 않고 전체 범위에 붙인다.
            let natural = textFont.lineHeight
            if style.textLineHeight > natural {
                let paragraph = NSMutableParagraphStyle()
                paragraph.minimumLineHeight = style.textLineHeight
                result.addAttribute(
                    .paragraphStyle,
                    value: paragraph,
                    range: NSRange(location: 0, length: result.length)
                )
            }
        }
        return result
    }

    // MARK: - TextKit

    static func configure(_ textContainer: NSTextContainer) {
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
    }

    /// Used size of `layoutManager`'s text at its container's current width, rounded up to
    /// whole points.
    static func usedSize(_ layoutManager: NSLayoutManager, _ textContainer: NSTextContainer) -> CGSize {
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: max(0, ceil(usedRect.width)), height: max(0, ceil(usedRect.height)))
    }

    /// Lays `attributed` out at `width` on a TextKit stack owned by this call (safe off the
    /// main thread) and returns the used size.
    static func measure(_ attributed: NSAttributedString, width: CGFloat) -> CGSize {
        guard attributed.length > 0 else { return .zero }
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        configure(textContainer)
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        // Assign the text the way RaTeXInlineView does (setAttributedString on an attached
        // storage), not through NSTextStorage(attributedString:). Measured on iOS 26: with the
        // initializer, a line made only of Hangul (font fallback to Apple SD Gothic Neo) came
        // out 24.45pt tall instead of the 24pt the view lays out, so the measured height
        // differed from the drawn one.
        textStorage.setAttributedString(attributed)
        layoutManager.ensureLayout(for: textContainer)
        return usedSize(layoutManager, textContainer)
    }

    #if !os(macOS)
    /// Bounds of a formula attachment. The bitmap is sized up to whole device pixels and the
    /// depth rounded to the nearest pixel (see RaTeXTextAttachment); the measurement uses the
    /// same numbers so both lay out identically.
    static func attachmentBounds(width: CGFloat, totalHeight: CGFloat, depth: CGFloat, scale: CGFloat) -> CGRect {
        let snapUp = { (v: CGFloat) in ceil(v * scale) / scale }
        let snap = { (v: CGFloat) in (v * scale).rounded() / scale }
        return CGRect(x: 0, y: -snap(depth), width: snapUp(width), height: snapUp(totalHeight))
    }
    #endif

    // MARK: - Fonts

    static func makeTextFont(_ style: RaTeXInlineTextStyle) -> PlatformFont {
        #if os(macOS)
        return resolveMacTextFont(family: style.textFontFamily, size: style.textFontSize, italic: style.textItalic)
        #else
        return resolveIOSTextFont(family: style.textFontFamily, size: style.textFontSize, italic: style.textItalic)
        #endif
    }

    private static let fontNamesLock = NSLock()

    #if os(macOS)
    private static func resolveMacTextFont(
        family: String?,
        size: CGFloat,
        italic: Bool
    ) -> NSFont {
        guard let family, !family.isEmpty else {
            return italic
                ? NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
                : NSFont.systemFont(ofSize: size)
        }

        if let font = bestMacFont(from: macFontNames(for: family), size: size, italic: italic) {
            return font
        }
        if let font = NSFont(name: family, size: size) {
            return italic ? macFontByApplyingItalic(font, size: size) : font
        }
        if let font = bestMacFont(from: fuzzyMacFontNames(matching: family), size: size, italic: italic) {
            return font
        }

        return italic
            ? NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
            : NSFont.systemFont(ofSize: size)
    }

    private static func macFontNames(for family: String) -> [String] {
        if let members = NSFontManager.shared.availableMembers(ofFontFamily: family), !members.isEmpty {
            return members.compactMap { $0.first as? String }
        }
        let matchedFamily = NSFontManager.shared.availableFontFamilies.first {
            fontIdentifierMatches($0, family)
        }
        guard let matchedFamily,
              let members = NSFontManager.shared.availableMembers(ofFontFamily: matchedFamily)
        else { return [] }
        return members.compactMap { $0.first as? String }
    }

    private static var fuzzyMacFontNamesCache: [String: [String]] = [:]

    private static func fuzzyMacFontNames(matching query: String) -> [String] {
        fontNamesLock.lock()
        defer { fontNamesLock.unlock() }
        if let cached = fuzzyMacFontNamesCache[query] { return cached }
        let result = NSFontManager.shared.availableFonts.filter {
            fontIdentifierMatches($0, query)
        }
        fuzzyMacFontNamesCache[query] = result
        return result
    }

    private static func bestMacFont(from names: [String], size: CGFloat, italic: Bool) -> NSFont? {
        names.reduce(nil as NSFont?) { best, name in
            guard let font = NSFont(name: name, size: size) else { return best }
            guard let currentBest = best else { return font }
            return macFontScore(font, italic: italic) < macFontScore(currentBest, italic: italic)
                ? font : currentBest
        }.map { italic ? macFontByApplyingItalic($0, size: size) : $0 }
    }

    private static func macFontScore(_ font: NSFont, italic: Bool) -> Int {
        var score = isMacItalicFont(font) == italic ? 0 : 1_000
        let name = font.fontName.lowercased()
        if italic {
            if name.contains("italic") || name.contains("oblique") {
                score -= 100
            }
        } else {
            if name.contains("regular") || name.contains("roman") || name.contains("normal") {
                score -= 100
            }
            if name.contains("bold") || name.contains("black") || name.contains("heavy") {
                score += 50
            }
        }
        return score
    }

    private static func isMacItalicFont(_ font: NSFont) -> Bool {
        NSFontManager.shared.traits(of: font).contains(.italicFontMask)
    }

    private static func macFontByApplyingItalic(_ font: NSFont, size: CGFloat) -> NSFont {
        guard !isMacItalicFont(font) else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
    #else
    private static func resolveIOSTextFont(
        family: String?,
        size: CGFloat,
        italic: Bool
    ) -> UIFont {
        guard let family, !family.isEmpty else {
            return italic ? UIFont.italicSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        }

        if let font = bestUIFont(from: iosFontNames(for: family), size: size, italic: italic) {
            return font
        }
        if let font = UIFont(name: family, size: size) {
            return italic ? uiFontByApplyingItalic(font, size: size) : font
        }
        if let font = bestUIFont(from: fuzzyIOSFontNames(matching: family), size: size, italic: italic) {
            return font
        }

        return italic ? UIFont.italicSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
    }

    private static func iosFontNames(for family: String) -> [String] {
        let names = UIFont.fontNames(forFamilyName: family)
        if !names.isEmpty { return names }

        guard let matchedFamily = UIFont.familyNames.first(where: {
            fontIdentifierMatches($0, family)
        }) else { return [] }
        return UIFont.fontNames(forFamilyName: matchedFamily)
    }

    private static var fuzzyIOSFontNamesCache: [String: [String]] = [:]

    private static func fuzzyIOSFontNames(matching query: String) -> [String] {
        fontNamesLock.lock()
        defer { fontNamesLock.unlock() }
        if let cached = fuzzyIOSFontNamesCache[query] { return cached }
        let result = UIFont.familyNames
            .flatMap { UIFont.fontNames(forFamilyName: $0) }
            .filter { fontIdentifierMatches($0, query) }
        fuzzyIOSFontNamesCache[query] = result
        return result
    }

    private static func bestUIFont(from names: [String], size: CGFloat, italic: Bool) -> UIFont? {
        names.reduce(nil as UIFont?) { best, name in
            guard let font = UIFont(name: name, size: size) else { return best }
            guard let currentBest = best else { return font }
            return uiFontScore(font, italic: italic) < uiFontScore(currentBest, italic: italic)
                ? font : currentBest
        }.map { italic ? uiFontByApplyingItalic($0, size: size) : $0 }
    }

    private static func uiFontScore(_ font: UIFont, italic: Bool) -> Int {
        var score = isUIItalicFont(font) == italic ? 0 : 1_000
        let name = font.fontName.lowercased()
        if italic {
            if name.contains("italic") || name.contains("oblique") {
                score -= 100
            }
        } else {
            if name.contains("regular") || name.contains("roman") || name.contains("normal") {
                score -= 100
            }
            if name.contains("bold") || name.contains("black") || name.contains("heavy") {
                score += 50
            }
        }
        return score
    }

    private static func isUIItalicFont(_ font: UIFont) -> Bool {
        let traits = font.fontDescriptor.symbolicTraits
        return traits.contains(.traitItalic)
            || font.fontName.lowercased().contains("italic")
            || font.fontName.lowercased().contains("oblique")
    }

    private static func uiFontByApplyingItalic(_ font: UIFont, size: CGFloat) -> UIFont {
        guard !isUIItalicFont(font) else { return font }
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return UIFont.italicSystemFont(ofSize: size)
    }
    #endif

    private static func fontIdentifierMatches(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.caseInsensitiveCompare(rhs) == .orderedSame {
            return true
        }
        let normalizedLhs = normalizedFontIdentifier(lhs)
        let normalizedRhs = normalizedFontIdentifier(rhs)
        if !normalizedLhs.isEmpty && normalizedLhs == normalizedRhs {
            return true
        }
        let compactLhs = compactFontIdentifier(lhs)
        let compactRhs = compactFontIdentifier(rhs)
        return !compactLhs.isEmpty && compactLhs == compactRhs
    }

    private static func normalizedFontIdentifier(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9]+",
                with: "_",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func compactFontIdentifier(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9]+",
                with: "",
                options: .regularExpression
            )
    }

    // MARK: - Parsing

    enum Segment {
        case text(String)
        case formula(String)
    }

    static func parseContent(_ content: String) -> [Segment] {
        var segments: [Segment] = []
        var current = ""
        var inFormula = false
        var index = content.startIndex

        while index < content.endIndex {
            let ch = content[index]
            let nextIndex = content.index(after: index)
            if ch == "\\", nextIndex < content.endIndex, content[nextIndex] == "$" {
                if inFormula {
                    current.append("\\$")
                } else {
                    current.append("$")
                }
                index = content.index(after: nextIndex)
                continue
            }

            if ch == "$" {
                if inFormula {
                    if !current.isEmpty {
                        segments.append(.formula(current))
                    } else {
                        segments.append(.text("$$"))
                    }
                    current = ""
                    inFormula = false
                } else {
                    if !current.isEmpty {
                        segments.append(.text(current))
                    }
                    current = ""
                    inFormula = true
                }
            } else {
                current.append(ch)
            }
            index = nextIndex
        }

        if inFormula {
            segments.append(.text("$\(current)"))
        } else if !current.isEmpty {
            segments.append(.text(current))
        }

        return segments
    }
}

#if !os(macOS)
/// Thread-safe measurement of an InlineTeX string, called by the Fabric shadow node's
/// `measureContent` so Yoga lays the view out at its real height on the commit that changes
/// the content. Without it the view kept whatever height JS gave it until the native view
/// laid out and sent onContentSizeChange, which dropped to one line on every content change.
@objc(RaTeXInlineMeasure)
public final class RaTeXInlineMeasure: NSObject {

    /// `maxWidth` is the width available to the text (CGFloat.greatestFiniteMagnitude when
    /// unconstrained); `scale` is the screen scale used to snap formula bitmaps.
    @objc public static func measureContent(
        _ content: String,
        fontSize: CGFloat,
        textFontSize: CGFloat,
        textFontFamily: String?,
        textLineHeight: CGFloat,
        textItalic: Bool,
        textUnderline: Bool,
        textLineThrough: Bool,
        maxWidth: CGFloat,
        scale: CGFloat
    ) -> CGSize {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .zero }
        let trimmedFamily = textFontFamily?.trimmingCharacters(in: .whitespacesAndNewlines)
        let style = RaTeXInlineTextStyle(
            formulaFontSize: fontSize,
            textFontSize: textFontSize,
            textFontFamily: trimmedFamily,
            textLineHeight: textLineHeight,
            textItalic: textItalic,
            textUnderline: textUnderline,
            textLineThrough: textLineThrough
        )
        let pixelScale = scale > 0 ? scale : 1
        let attributed = RaTeXInlineLayout.attributedString(
            content: content,
            style: style,
            textColor: .black
        ) { latex in
            guard let displayList = try? RaTeXEngine.shared.parse(latex, displayMode: false, color: .black) else {
                return nil
            }
            let renderer = RaTeXRenderer(displayList: displayList, fontSize: fontSize)
            // Same shape as RaTeXTextAttachment, without drawing the bitmap.
            let attachment = NSTextAttachment(data: nil, ofType: nil)
            if renderer.width > 0, renderer.totalHeight > 0 {
                attachment.bounds = RaTeXInlineLayout.attachmentBounds(
                    width: renderer.width,
                    totalHeight: renderer.totalHeight,
                    depth: renderer.depth,
                    scale: pixelScale
                )
            }
            return attachment
        }
        let width = maxWidth.isFinite && maxWidth > 0 ? maxWidth : CGFloat.greatestFiniteMagnitude
        return RaTeXInlineLayout.measure(attributed, width: width)
    }
}
#endif
