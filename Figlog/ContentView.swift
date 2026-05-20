//
//  ContentView.swift
//  Figlog
//
//  Created by 권민재 on 5/21/26.
//

import SwiftUI
import AppKit
import Combine

struct ContentView: View {

    @State private var isTracking = false
    @State private var isIdle = false
    @State private var focusTime: TimeInterval = 0

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {

        VStack(spacing: 20) {

            Text("FigLog")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Track your real Figma focus time")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(formattedTime)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 12) {

                Circle()
                    .fill(isTracking ? .green : .gray)
                    .frame(width: 10, height: 10)

                Text(statusText)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 320)
        .onReceive(timer) { _ in

            let activeApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

            let idleTime = CGEventSource.secondsSinceLastEventType(
                .hidSystemState,
                eventType: .mouseMoved
            )

            isIdle = idleTime >= 10

            if activeApp == "com.figma.Desktop" && !isIdle {

                isTracking = true
                focusTime += 1

            } else {

                isTracking = false
            }
        }
    }

    var statusText: String {

        if isTracking {
            return "Tracking Figma"
        }

        if isIdle {
            return "Idle"
        }

        return "Waiting for Figma"
    }

    var formattedTime: String {

        let hours = Int(focusTime) / 3600
        let minutes = (Int(focusTime) % 3600) / 60
        let seconds = Int(focusTime) % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
