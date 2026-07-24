import AppKit
import QuartzCore

enum LookDirection: String, CaseIterable {
    case left
    case right
    case up
    case down
    case upLeft
    case upRight
    case downLeft
    case downRight
}

final class CatPetView: NSView {
    weak var appDelegate: AppDelegate?

    var isAnimationPaused = false {
        didSet {
            if !isAnimationPaused {
                lastFrameTime = CACurrentMediaTime()
            }
            needsDisplay = true
        }
    }

    private let neutralImage: NSImage
    private let blinkImage: NSImage
    private let directionImages: [LookDirection: NSImage]

    private var displayTimer: Timer?
    private var lastFrameTime = CACurrentMediaTime()
    private var elapsed: TimeInterval = 0
    private var nextBlinkTime: TimeInterval = 3.2
    private var blinkStart: TimeInterval?
    private var bounceStart: TimeInterval?
    private var isResting = false

    private var activeDirection: LookDirection?
    private var previousDirection: LookDirection?
    private var directionTransition: CGFloat = 1
    private var poseStrength: CGFloat = 0
    private var targetPoseStrength: CGFloat = 0
    private var isCursorEngaged = false

    private var dragStartOnScreen: NSPoint?
    private var windowStartOrigin: NSPoint?
    private var pendingSingleClick: DispatchWorkItem?

    init(
        neutralImage: NSImage,
        blinkImage: NSImage,
        directionImages: [LookDirection: NSImage]
    ) {
        self.neutralImage = neutralImage
        self.blinkImage = blinkImage
        self.directionImages = directionImages
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        startAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayTimer?.invalidate()
    }

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let imageRect = fittedImageRect(in: bounds)
        guard imageRect.contains(point) else { return nil }

        let normalized = CGPoint(
            x: (point.x - imageRect.minX) / imageRect.width,
            y: (point.y - imageRect.minY) / imageRect.height
        )
        guard let cgImage = neutralImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return self
        }

        let pixelX = min(max(Int(normalized.x * CGFloat(cgImage.width)), 0), cgImage.width - 1)
        let pixelYFromBottom = min(max(Int(normalized.y * CGFloat(cgImage.height)), 0), cgImage.height - 1)
        let pixelY = cgImage.height - 1 - pixelYFromBottom

        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              cgImage.bitsPerPixel >= 32
        else {
            return self
        }

        let index = pixelY * cgImage.bytesPerRow + pixelX * 4
        let alpha: UInt8
        switch cgImage.alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst:
            alpha = bytes[index]
        default:
            alpha = bytes[index + 3]
        }
        return alpha > 18 ? self : nil
    }

    private func startAnimation() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.advanceAnimation()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func advanceAnimation() {
        let now = CACurrentMediaTime()
        let delta = min(now - lastFrameTime, 0.1)
        lastFrameTime = now

        guard !isAnimationPaused else { return }
        elapsed += delta
        updateTargetPose()

        let poseSmoothing = 1.0 - pow(0.0005, delta)
        poseStrength += (targetPoseStrength - poseStrength) * poseSmoothing
        directionTransition = min(1, directionTransition + CGFloat(delta / 0.12))

        if elapsed >= nextBlinkTime, blinkStart == nil, poseStrength < 0.12 {
            blinkStart = elapsed
            nextBlinkTime = elapsed + Double.random(in: 3.4...7.2)
        }
        if let start = blinkStart, elapsed - start > 0.24 {
            blinkStart = nil
        }
        if let start = bounceStart, elapsed - start > 0.55 {
            bounceStart = nil
        }

        needsDisplay = true
    }

    private func updateTargetPose() {
        guard let window else { return }

        let mouse = NSEvent.mouseLocation
        let center = window.convertPoint(
            toScreen: NSPoint(x: bounds.midX, y: bounds.height * 0.73)
        )
        let rawX = mouse.x - center.x
        let rawY = mouse.y - center.y
        let distance = hypot(rawX, rawY)

        if isCursorEngaged {
            if distance > 600 {
                isCursorEngaged = false
            }
        } else if distance < 500 {
            isCursorEngaged = true
        }

        if isResting, !isCursorEngaged {
            targetPoseStrength = 0.92
            changeDirection(to: .down)
            return
        }

        targetPoseStrength = isCursorEngaged && distance >= 28 ? 1 : 0
        guard targetPoseStrength > 0 else { return }
        changeDirection(to: direction(forX: rawX, y: rawY))
    }

    private func changeDirection(to newDirection: LookDirection) {
        guard activeDirection != newDirection else { return }
        previousDirection = activeDirection
        activeDirection = newDirection
        directionTransition = 0
        blinkStart = nil
    }

    private func direction(forX x: CGFloat, y: CGFloat) -> LookDirection {
        let degrees = atan2(y, x) * 180 / .pi
        switch degrees {
        case -22.5..<22.5:
            return .right
        case 22.5..<67.5:
            return .upRight
        case 67.5..<112.5:
            return .up
        case 112.5..<157.5:
            return .upLeft
        case 157.5...180, -180..<(-157.5):
            return .left
        case -157.5..<(-112.5):
            return .downLeft
        case -112.5..<(-67.5):
            return .down
        default:
            return .downRight
        }
    }

    private var blinkAmount: CGFloat {
        guard !isResting, poseStrength < 0.12, let start = blinkStart else {
            return 0
        }
        let phase = max(0, min((elapsed - start) / 0.24, 1))
        return CGFloat(sin(phase * .pi))
    }

    private var bounceAmount: CGFloat {
        guard let start = bounceStart else { return 0 }
        let phase = max(0, min((elapsed - start) / 0.55, 1))
        return CGFloat(sin(phase * .pi))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let baseRect = fittedImageRect(in: bounds)
        let breathing = isAnimationPaused
            ? 0
            : CGFloat(sin(elapsed * (isResting ? 1.1 : 1.7))) * 0.004
        let bounce = bounceAmount
        let drawRect = NSRect(
            x: baseRect.minX - baseRect.width * bounce * 0.012,
            y: baseRect.minY + bounce * 10,
            width: baseRect.width * (1 + bounce * 0.024),
            height: baseRect.height * (1 + breathing + bounce * 0.018)
        )

        let easedTransition = directionTransition * directionTransition * (3 - 2 * directionTransition)
        let neutralFraction = max(0, 1 - poseStrength)
        draw(neutralImage, in: drawRect, fraction: neutralFraction)

        if poseStrength > 0.001 {
            if directionTransition < 1 {
                draw(
                    image(for: previousDirection),
                    in: drawRect,
                    fraction: poseStrength * (1 - easedTransition)
                )
            }
            draw(
                image(for: activeDirection),
                in: drawRect,
                fraction: poseStrength * easedTransition
            )
        }

        if blinkAmount > 0.001 {
            draw(blinkImage, in: drawRect, fraction: blinkAmount)
        }
    }

    private func image(for direction: LookDirection?) -> NSImage {
        guard let direction else { return neutralImage }
        return directionImages[direction] ?? neutralImage
    }

    private func draw(_ image: NSImage, in rect: NSRect, fraction: CGFloat) {
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: fraction,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func fittedImageRect(in rect: NSRect) -> NSRect {
        let ratio = neutralImage.size.width / neutralImage.size.height
        var size = NSSize(width: rect.height * ratio, height: rect.height)
        if size.width > rect.width {
            size = NSSize(width: rect.width, height: rect.width / ratio)
        }
        return NSRect(
            x: rect.midX - size.width / 2,
            y: rect.minY,
            width: size.width,
            height: size.height
        )
    }

    override func mouseDown(with event: NSEvent) {
        dragStartOnScreen = NSEvent.mouseLocation
        windowStartOrigin = window?.frame.origin

        pendingSingleClick?.cancel()
        if event.clickCount >= 2 {
            isResting.toggle()
            blinkStart = nil
            needsDisplay = true
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.playInteraction()
            }
            pendingSingleClick = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + NSEvent.doubleClickInterval,
                execute: workItem
            )
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let startMouse = dragStartOnScreen,
            let startOrigin = windowStartOrigin,
            let window
        else { return }

        pendingSingleClick?.cancel()
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: startOrigin.x + current.x - startMouse.x,
            y: startOrigin.y + current.y - startMouse.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartOnScreen = nil
        windowStartOrigin = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        appDelegate?.showContextMenu(event: event, from: self)
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 0.1 else { return }
        appDelegate?.adjustScale(by: event.scrollingDeltaY > 0 ? 0.1 : -0.1)
    }

    override func magnify(with event: NSEvent) {
        guard abs(event.magnification) > 0.002 else { return }
        appDelegate?.adjustScale(by: event.magnification)
    }

    private func playInteraction() {
        bounceStart = elapsed
        NSSound(named: NSSound.Name("Pop"))?.play()
    }
}
