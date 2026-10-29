import UIKit
import XCTest

/// sRGB raster measurement of an actual native Text crop; not a palette-token assertion.
@MainActor
enum TranslationContrastPixels {
    struct Measurement {
        let ratio: Double
        let foreground: [Int]
        let background: [Int]
        let foregroundCount: Int
        let backgroundCount: Int
        let pixels: Int
        var description: String {
            "sRGB opaque foreground=\(foreground) background=\(background) ratio=\(ratio); "
                + "plateau=\(foregroundCount), background=\(backgroundCount), pixels=\(pixels)"
        }
    }
    enum Invalid: Error { case bitmap, transparent, ambiguousBackground, ambiguousInk }
    static func luminance(_ rgb: [Int]) -> Double {
        let c = rgb.map { Double($0) / 255 }.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }
    static func ratio(_ a: [Int], _ b: [Int]) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    static func measure(_ image: CGImage) throws -> Measurement {
        let width = image.width, height = image.height, count = width * height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw Invalid.bitmap }
        var bytes = [UInt8](repeating: 0, count: count * 4)
        let rendered = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw Invalid.bitmap }
        var histogram: [Int: Int] = [:]
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            // This measurement deliberately accepts only a fully composited opaque host/crop.
            // Never discard alpha or accidentally treat premultiplied transparent pixels as ink.
            guard bytes[offset + 3] == 255 else { throw Invalid.transparent }
            let key = Int(bytes[offset]) << 16 | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2])
            histogram[key, default: 0] += 1
        }
        func rgb(_ key: Int) -> [Int] { [(key >> 16) & 255, (key >> 8) & 255, key & 255] }
        let sorted = histogram.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard let backdrop = sorted.first, backdrop.value >= count * 35 / 100 else { throw Invalid.ambiguousBackground }
        let background = rgb(backdrop.key)
        let candidates = sorted.dropFirst().filter {
            let color = rgb($0.key)
            return ratio(color, background) >= 1.3 && color.max()! - color.min()! <= 32
        }
        guard let ink = candidates.first, ink.value >= min(256, max(48, count / 200)) else { throw Invalid.ambiguousInk }
        let foreground = rgb(ink.key)
        if candidates.dropFirst().contains(where: {
            $0.value >= ink.value / 2 && abs(ratio(rgb($0.key), background) - ratio(foreground, background)) > 0.75
        }) { throw Invalid.ambiguousInk }
        return Measurement(ratio: ratio(foreground, background), foreground: foreground, background: background,
                           foregroundCount: ink.value, backgroundCount: backdrop.value, pixels: count)
    }
    static func keep(_ image: UIImage, name: String, in test: XCTestCase) {
        let attachment = XCTAttachment(image: image); attachment.name = name
        attachment.lifetime = .keepAlways; test.add(attachment)
    }
}
