import AppKit
import CoreText
import SwiftUI

enum StandbyFonts {
    /// SF Compact Rounded ships with macOS but isn't exposed by name, so it's
    /// loaded from its file and set to a weight on its variable axis.
    nonisolated(unsafe) private static let compactRoundedDescriptor: CTFontDescriptor? = {
        let url = URL(fileURLWithPath: "/System/Library/Fonts/SFCompactRounded.ttf") as CFURL
        return (CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor])?.first
    }()

    /// `weight` is on the font's 1–1000 axis (400 regular, 700 bold, 1000 black).
    static func compactRounded(size: CGFloat, weight: CGFloat) -> Font {
        guard let base = compactRoundedDescriptor else {
            return .system(size: size, weight: .black, design: .rounded)
        }
        let wght = 0x7767_6874 as CFNumber // 'wght'
        let descriptor = CTFontDescriptorCreateCopyWithVariation(base, wght, weight)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}
