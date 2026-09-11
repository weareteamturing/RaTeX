// RaTeXUnicodeFont.swift — lets the host app choose the font RaTeX uses for glyphs
// outside the KaTeX fonts (CJK text inside $…$, for example).

import CoreText
import Foundation

/// The Rust core falls back to a *system sans* font for any character the KaTeX fonts
/// lack, and reads `RATEX_UNICODE_FONT` (a file path) as the highest-priority override.
/// The result is cached on first use, so the variable must be set before the first render —
/// `RaTeXEngine` calls this from its initializer.
///
/// Declare the font in Info.plist by resource name (it must be a bundled resource,
/// e.g. one already listed under `UIAppFonts`):
///
/// ```xml
/// <key>RaTeXUnicodeFont</key>
/// <string>NotoSerifKR-Regular.otf</string>
/// ```
enum RaTeXUnicodeFont {
    private static let plistKey = "RaTeXUnicodeFont"
    private static let envKey = "RATEX_UNICODE_FONT"

    /// PostScript name the renderer draws `CJK-Regular` glyphs with. The Rust core only lays
    /// glyphs out (it reads the same file through RATEX_UNICODE_FONT for advance widths);
    /// drawing happens in RaTeXRenderer with CoreText, so the face has to be chosen here too.
    /// Nil = CoreText's own cascade (system sans for CJK).
    private(set) static var postScriptName: String?

    static func configureFromInfoPlist() {
        guard let name = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String,
              !name.isEmpty
        else { return }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let path = Bundle.main.path(forResource: base, ofType: ext.isEmpty ? nil : ext) else {
            NSLog("[RaTeXUnicodeFont] '%@' is not a bundled resource; %@ left unset", name, envKey)
            return
        }
        setenv(envKey, path, 1)

        let url = URL(fileURLWithPath: path)
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let first = descriptors.first,
           let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String {
            // Register in case the app did not list it under UIAppFonts. Errors (already registered) are fine.
            if !RaTeXFontLoader.isFontRegistered(name) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            postScriptName = name
        }
    }
}
