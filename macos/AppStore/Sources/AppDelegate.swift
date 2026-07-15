import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var actionMenuItem: NSMenuItem?
    private var hotKeyMonitor: HotKeyMonitor?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        observeModel()
        registerHotKey()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func registerHotKey() {
        let monitor = HotKeyMonitor(
            pressed: { [weak model] in model?.hotKeyPressed() },
            released: { [weak model] in model?.hotKeyReleased() }
        )
        do {
            try monitor.register()
            hotKeyMonitor = monitor
        } catch {
            model.reportShortcutFailure(error)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "OpenVoiceFlow")

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open OpenVoiceFlow", action: #selector(openWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let status = NSMenuItem(title: model.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        let action = NSMenuItem(title: model.actionTitle, action: #selector(toggleRecording), keyEquivalent: "")
        action.target = self
        menu.addItem(action)
        actionMenuItem = action

        menu.addItem(NSMenuItem(title: "Shortcut: Control+Option+Space", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit OpenVoiceFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    private func observeModel() {
        model.$statusText
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.statusMenuItem?.title = value }
            .store(in: &cancellables)
        model.$isRecording
            .combineLatest(model.$isBusy)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, busy in
                self?.actionMenuItem?.title = self?.model.actionTitle ?? "Start recording"
                self?.actionMenuItem?.isEnabled = !busy
            }
            .store(in: &cancellables)
    }

    @objc private func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleRecording() {
        model.toggleRecording()
    }
}
