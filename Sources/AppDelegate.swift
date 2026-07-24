import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let baseSize = NSSize(width: 300, height: 440)
    private let minimumScale: CGFloat = 0.55
    private let maximumScale: CGFloat = 1.80
    private var petScale: CGFloat = 1.0

    private var panel: PetPanel!
    private var petView: CatPetView!
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var visibilityItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var sizeItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let savedScale = CGFloat(UserDefaults.standard.double(forKey: "petScale"))
        if savedScale > 0 {
            petScale = min(max(savedScale, minimumScale), maximumScale)
        }
        createPetWindow()
        createStatusMenu()
    }

    private func createPetWindow() {
        let size = NSSize(
            width: baseSize.width * petScale,
            height: baseSize.height * petScale
        )
        panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        guard
            let neutralImage = loadImage(named: "cat-open.png"),
            let blinkImage = loadImage(named: "cat-eyes-blink.png")
        else {
            let alert = NSAlert()
            alert.messageText = "小猫素材缺失"
            alert.informativeText = "请重新构建应用，或检查 Resources 目录。"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        var directionImages: [LookDirection: NSImage] = [:]
        for direction in LookDirection.allCases {
            let fileName = "Directions/cat-\(resourceName(for: direction)).png"
            guard let image = loadImage(named: fileName) else {
                let alert = NSAlert()
                alert.messageText = "方向素材缺失"
                alert.informativeText = "缺少 \(fileName)，请重新构建应用。"
                alert.runModal()
                NSApp.terminate(nil)
                return
            }
            directionImages[direction] = image
        }

        petView = CatPetView(
            neutralImage: neutralImage,
            blinkImage: blinkImage,
            directionImages: directionImages
        )
        petView.appDelegate = self
        panel.contentView = petView

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.maxX - size.width - 28,
                y: visible.minY + 22
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
    }

    private func loadImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func resourceName(for direction: LookDirection) -> String {
        switch direction {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        case .down: return "down"
        case .upLeft: return "up-left"
        case .upRight: return "up-right"
        case .downLeft: return "down-left"
        case .downRight: return "down-right"
        }
    }

    private func createStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "pawprint.circle.fill",
            accessibilityDescription: "小橘桌宠"
        )
        statusItem.button?.toolTip = "小橘桌宠"

        menu = NSMenu(title: "小橘桌宠")
        menu.delegate = self

        let titleItem = NSMenuItem(title: "小橘桌宠", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        visibilityItem = NSMenuItem(
            title: "隐藏小猫",
            action: #selector(toggleVisibility),
            keyEquivalent: ""
        )
        visibilityItem.target = self
        menu.addItem(visibilityItem)

        pauseItem = NSMenuItem(
            title: "暂停动作",
            action: #selector(togglePaused),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        sizeItem = NSMenuItem(
            title: "大小：\(scalePercentage)",
            action: nil,
            keyEquivalent: ""
        )
        let sizeMenu = NSMenu(title: "调整大小")

        let largerItem = NSMenuItem(
            title: "放大",
            action: #selector(makeLarger),
            keyEquivalent: "+"
        )
        largerItem.target = self
        sizeMenu.addItem(largerItem)

        let smallerItem = NSMenuItem(
            title: "缩小",
            action: #selector(makeSmaller),
            keyEquivalent: "-"
        )
        smallerItem.target = self
        sizeMenu.addItem(smallerItem)

        let normalSizeItem = NSMenuItem(
            title: "恢复默认大小",
            action: #selector(resetScale),
            keyEquivalent: "0"
        )
        normalSizeItem.target = self
        sizeMenu.addItem(normalSizeItem)

        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        launchAtLoginItem = NSMenuItem(
            title: "开机启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let resetItem = NSMenuItem(
            title: "回到右下角",
            action: #selector(resetPosition),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        let quitItem = NSMenuItem(
            title: "退出小橘桌宠",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshMenuState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    func showContextMenu(event: NSEvent, from view: NSView) {
        refreshMenuState()
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func toggleVisibility() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
        refreshMenuState()
    }

    @objc private func togglePaused() {
        petView.isAnimationPaused.toggle()
        refreshMenuState()
    }

    @objc private func makeLarger() {
        adjustScale(by: 0.1)
    }

    @objc private func makeSmaller() {
        adjustScale(by: -0.1)
    }

    @objc private func resetScale() {
        setScale(1.0)
    }

    func adjustScale(by amount: CGFloat) {
        setScale(petScale + amount)
    }

    private func setScale(_ requestedScale: CGFloat) {
        let newScale = min(max(requestedScale, minimumScale), maximumScale)
        guard abs(newScale - petScale) > 0.001 else { return }

        let oldFrame = panel.frame
        petScale = newScale
        let newSize = NSSize(
            width: baseSize.width * petScale,
            height: baseSize.height * petScale
        )
        var newOrigin = NSPoint(
            x: oldFrame.midX - newSize.width / 2,
            y: oldFrame.minY
        )

        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            newOrigin.x = min(max(newOrigin.x, visible.minX), visible.maxX - newSize.width)
            newOrigin.y = min(max(newOrigin.y, visible.minY), visible.maxY - newSize.height)
        }

        panel.setFrame(
            NSRect(origin: newOrigin, size: newSize),
            display: true,
            animate: true
        )
        UserDefaults.standard.set(Double(petScale), forKey: "petScale")
        refreshMenuState()
    }

    private var scalePercentage: String {
        "\(Int((petScale * 100).rounded()))%"
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }

        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .notRegistered, .notFound:
                try SMAppService.mainApp.register()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            @unknown default:
                break
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改开机启动"
            alert.informativeText = "\(error.localizedDescription)\n\n未签名或临时签名的应用可能需要在“系统设置 → 通用 → 登录项”中手动添加。"
            alert.runModal()
        }
        refreshMenuState()
    }

    @objc private func resetPosition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - panel.frame.width - 28,
            y: visible.minY + 22
        ))
        panel.orderFrontRegardless()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func refreshMenuState() {
        visibilityItem?.title = panel?.isVisible == true ? "隐藏小猫" : "显示小猫"
        pauseItem?.state = petView?.isAnimationPaused == true ? .on : .off
        sizeItem?.title = "大小：\(scalePercentage)"

        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                launchAtLoginItem?.state = .on
                launchAtLoginItem?.title = "开机启动"
            case .requiresApproval:
                launchAtLoginItem?.state = .mixed
                launchAtLoginItem?.title = "开机启动（需要批准）"
            default:
                launchAtLoginItem?.state = .off
                launchAtLoginItem?.title = "开机启动"
            }
        }
    }
}
