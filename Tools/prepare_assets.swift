import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct RGBAImage {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    var pixels: [UInt8]

    init(url: URL) throws {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw NSError(domain: "AssetPrep", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot load \(url.path)"
            ])
        }

        width = image.width
        height = image.height
        bytesPerRow = width * 4
        pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "AssetPrep", code: 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func write(to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            ),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw NSError(domain: "AssetPrep", code: 3)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "AssetPrep", code: 4)
        }
    }

    func eyePatch(ellipses: [(Double, Double, Double, Double)]) -> RGBAImage {
        var output = self
        for y in 0..<height {
            for x in 0..<width {
                var mask = 0.0
                for ellipse in ellipses {
                    let dx = (Double(x) - ellipse.0) / ellipse.2
                    let dy = (Double(y) - ellipse.1) / ellipse.3
                    let radius = sqrt(dx * dx + dy * dy)
                    let feather = 1 - smoothstep(0.50, 1.0, radius)
                    mask = max(mask, feather)
                }
                let index = y * bytesPerRow + x * 4
                for channel in 0..<4 {
                    output.pixels[index + channel] = UInt8(
                        Double(output.pixels[index + channel]) * mask
                    )
                }
            }
        }
        return output
    }

    func squareIcon(size: Int) -> RGBAImage {
        var output = RGBAImage(width: size, height: size)
        let scale = min(Double(size) * 0.84 / Double(width), Double(size) * 0.90 / Double(height))
        let targetWidth = Double(width) * scale
        let targetHeight = Double(height) * scale
        let xOffset = (Double(size) - targetWidth) / 2
        let yOffset = (Double(size) - targetHeight) / 2

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        output.pixels.withUnsafeMutableBytes { destinationBytes in
            guard let context = CGContext(
                data: destinationBytes.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }

            let colors = [
                NSColor(calibratedRed: 0.98, green: 0.76, blue: 0.30, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.90, green: 0.39, blue: 0.12, alpha: 1).cgColor
            ] as CFArray
            let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: colors,
                locations: [0, 1]
            )!
            let inset = CGFloat(size) * 0.06
            let background = CGPath(
                roundedRect: CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2),
                cornerWidth: CGFloat(size) * 0.22,
                cornerHeight: CGFloat(size) * 0.22,
                transform: nil
            )
            context.saveGState()
            context.addPath(background)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: CGFloat(size)),
                end: CGPoint(x: CGFloat(size), y: 0),
                options: []
            )
            context.restoreGState()

            guard
                let provider = CGDataProvider(data: Data(pixels) as CFData),
                let image = CGImage(
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: true,
                    intent: .defaultIntent
                )
            else { return }

            context.draw(
                image,
                in: CGRect(x: xOffset, y: yOffset - Double(size) * 0.02, width: targetWidth, height: targetHeight)
            )
        }
        return output
    }

    private init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bytesPerRow = width * 4
        pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    }
}

func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = max(0, min((x - edge0) / (edge1 - edge0), 1))
    return t * t * (3 - 2 * t)
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: prepare_assets <open.png> <blink.png> <output-directory>\n", stderr)
    exit(2)
}

let openURL = URL(fileURLWithPath: CommandLine.arguments[1])
let blinkURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)

do {
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    let open = try RGBAImage(url: openURL)
    let blink = try RGBAImage(url: blinkURL)

    guard open.width == blink.width, open.height == blink.height else {
        throw NSError(domain: "AssetPrep", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "Open and blink images must use the same canvas size."
        ])
    }

    let eyeEllipses = [
        (Double(open.width) * 0.455, Double(open.height) * 0.270, Double(open.width) * 0.060, Double(open.height) * 0.026),
        (Double(open.width) * 0.635, Double(open.height) * 0.270, Double(open.width) * 0.060, Double(open.height) * 0.026)
    ]

    try blink.eyePatch(ellipses: eyeEllipses).write(
        to: outputURL.appendingPathComponent("cat-eyes-blink.png")
    )
    try open.squareIcon(size: 1024).write(
        to: outputURL.appendingPathComponent("AppIcon-1024.png")
    )
    print("Prepared layered cat assets in \(outputURL.path)")
} catch {
    fputs("Asset preparation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
