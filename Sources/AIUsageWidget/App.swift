import AppKit
import SwiftUI
import WidgetKit

@MainActor
final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar usage widget stays resident")

        store = Store()
        store.openSettings = { [weak self] in self?.showSettings() }

        setupStatusItem()
        store.publishWidgetSnapshot()
        store.refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.50percent",
                accessibilityDescription: "AI Usage"
            )
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(item("Refresh now", #selector(refresh)))
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))

        let dashboards = NSMenuItem(title: "Open dashboard", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for kind in ProviderKind.allCases {
            let entry = item(kind.title, #selector(openDashboard(_:)))
            entry.representedObject = kind.rawValue
            submenu.addItem(entry)
        }
        dashboards.submenu = submenu
        menu.addItem(dashboards)

        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(NSApplication.terminate(_:)), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refresh() {
        store.refresh()
    }

    @objc private func openDashboard(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = ProviderKind(rawValue: raw)
        else { return }
        NSWorkspace.shared.open(kind.dashboardURL)
    }

    @objc private func didWake() {
        Task { @MainActor in store.refresh() }
    }

    // MARK: - Settings

    @objc func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(store: store) { [weak self] in
                self?.settingsWindow?.orderOut(nil)
            })
            let size = NSSize(width: 430, height: 476)
            let window = SettingsWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = true
            window.contentViewController = controller
            window.setContentSize(size)
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking the widget should not force the settings panel open.
        false
    }
}
