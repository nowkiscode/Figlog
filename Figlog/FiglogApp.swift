//
//  FiglogApp.swift
//  Figlog
//
//  Created by 권민재 on 5/21/26.
//

import SwiftUI
import AppKit
import FirebaseCore

@main
struct FiglogApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appLanguage") private var appLanguage = "en"

    var body: some Scene {
        Settings {
            SettingsView(tracker: appDelegate.tracker)
                .environment(\.locale, Locale(identifier: appLanguage))
        }
    }
}

struct PopoverRootView: View {
    @ObservedObject var tracker: FocusTracker
    @AppStorage("appLanguage") private var appLanguage = "en"
    
    var body: some View {
        ContentView(tracker: tracker)
            .environment(\.locale, Locale(identifier: appLanguage))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    let tracker = FocusTracker()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FirebaseApp.configure()
        
        Task { @MainActor in
            await FirebaseManager.shared.setupUser()
        }
        
        NSApp.setActivationPolicy(.accessory)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.contentViewController = NSHostingController(rootView: PopoverRootView(tracker: tracker))
        self.popover = popover

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "FigLog") {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.title = "FL"
            }

            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // tracker.stop() is now handled natively via NotificationCenter inside FocusTracker
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
