//
//  LaunchAtLoginController.swift
//  Figlog
//
//  Created by Codex on 5/21/26.
//

import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {

    @Published private(set) var isEnabled = false
    @Published private(set) var statusText = "Off"

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled

        switch status {
        case .enabled:
            statusText = "On"
        case .requiresApproval:
            statusText = "Needs approval"
        case .notRegistered:
            statusText = "Off"
        case .notFound:
            statusText = "Unavailable"
        @unknown default:
            statusText = "Unknown"
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusText = "Failed"
        }

        refresh()
    }
}
