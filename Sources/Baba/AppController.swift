import AppKit
import SwiftUI

/// Owns the menu bar item and the popover.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    static let shared = AppController()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.below.photo", accessibilityDescription: "Baba")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Baba — ⌥⌘M"
        }

        let root = ContentView()
            .environmentObject(Library.shared)
            .environmentObject(Session.shared)
        popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: root)

        HotkeyManager.shared.onTrigger = { [weak self] in self?.togglePopover() }
        HotkeyManager.shared.start()
        installKeyHandling()
    }

    /// An accessory app shows no menu bar, but AppKit still routes command-key
    /// equivalents through the main menu — without an Edit menu, ⌘V does
    /// nothing in a text field.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Baba", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// Escape steps back from the editor to the picker, then closes the panel.
    private func installKeyHandling() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            let command = event.modifierFlags.contains(.command)
            switch (event.keyCode, command, event.charactersIgnoringModifiers) {
            case (53, _, _):
                if Session.shared.template != nil {
                    Session.shared.template = nil
                } else {
                    self.closePopover()
                }
                return nil
            case (_, true, "w"):
                self.closePopover()
                return nil
            default:
                return event
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Template Folder", action: #selector(openFolder), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Reload Templates", action: #selector(reload), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Baba", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc private func openFolder() {
        try? FileManager.default.createDirectory(at: Library.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Library.root)
    }

    @objc private func reload() { Library.shared.reload() }

    func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        Session.shared.reset()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startWatchingForOutsideClicks()
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        // Hand focus back to whatever app the user was typing in.
        NSApp.hide(nil)
    }

    /// A transient popover would close mid-drag when a meme is dragged out, so
    /// dismissal is managed here. Only mouse-down is watched: the drag presses
    /// inside the panel and releases elsewhere.
    private func startWatchingForOutsideClicks() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                let frame = self.popover.contentViewController?.view.window?.frame ?? .zero
                if !frame.contains(NSEvent.mouseLocation) { self.closePopover() }
            }
        }
    }
}
