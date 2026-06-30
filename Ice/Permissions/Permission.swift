//
//  Permission.swift
//  Ice
//

import AXSwift
import Combine
import Cocoa
import ScreenCaptureKit

// MARK: - Permission

/// An object that encapsulates the behavior of checking for and requesting
/// a specific permission for the app.
@MainActor
class Permission: ObservableObject, Identifiable {
    /// A Boolean value that indicates whether the app has this permission.
    @Published private(set) var hasPermission = false

    /// The title of the permission.
    let title: String
    /// Descriptive details for the permission.
    let details: [String]
    /// A Boolean value that indicates if the app can work without this permission.
    let isRequired: Bool

    /// The URL of the settings pane to open.
    private let settingsURL: URL?
    /// The function that checks permissions.
    private let check: () -> Bool
    /// The function that requests permissions.
    private let request: () -> Void

    /// Observer that runs on a timer to check permissions.
    private var timerCancellable: AnyCancellable?
    /// Observer that observes the ``hasPermission`` property.
    private var hasPermissionCancellable: AnyCancellable?
    /// Continuation waiting for this permission to be granted.
    private var permissionContinuation: CheckedContinuation<Bool, Never>?

    /// Creates a permission.
    ///
    /// - Parameters:
    ///   - title: The title of the permission.
    ///   - details: Descriptive details for the permission.
    ///   - isRequired: A Boolean value that indicates if the app can work without this permission.
    ///   - settingsURL: The URL of the settings pane to open.
    ///   - check: A function that checks permissions.
    ///   - request: A function that requests permissions.
    init(
        title: String,
        details: [String],
        isRequired: Bool,
        settingsURL: URL?,
        check: @escaping () -> Bool,
        request: @escaping () -> Void
    ) {
        self.title = title
        self.details = details
        self.isRequired = isRequired
        self.settingsURL = settingsURL
        self.check = check
        self.request = request
        self.hasPermission = check()
        configureCancellables()
    }

    /// Sets up the internal observers for the permission.
    private func configureCancellables() {
        guard !hasPermission else {
            return
        }
        timerCancellable = Timer.publish(every: 1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                hasPermission = check()
                if hasPermission {
                    finishWaitingForPermission(granted: true)
                }
            }
    }

    /// Refreshes the current permission state.
    func refresh() {
        hasPermission = check()
        if hasPermission {
            finishWaitingForPermission(granted: true)
        } else {
            configureCancellables()
        }
    }

    /// Performs the request and opens the System Settings app to the appropriate pane.
    func performRequest() {
        request()
        refresh()
        if let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    /// Asynchronously waits for the app to be granted this permission.
    func waitForPermission() async -> Bool {
        guard !hasPermission else {
            return true
        }
        configureCancellables()
        return await withCheckedContinuation { continuation in
            permissionContinuation?.resume(returning: false)
            permissionContinuation = continuation
            hasPermissionCancellable = $hasPermission.sink { [weak self] hasPermission in
                if hasPermission {
                    self?.finishWaitingForPermission(granted: true)
                }
            }
        }
    }

    /// Finishes any active permission wait and stops polling.
    private func finishWaitingForPermission(granted: Bool) {
        timerCancellable?.cancel()
        timerCancellable = nil
        hasPermissionCancellable?.cancel()
        hasPermissionCancellable = nil
        permissionContinuation?.resume(returning: granted)
        permissionContinuation = nil
    }

    /// Stops running the permission check.
    func stopCheck() {
        finishWaitingForPermission(granted: false)
    }
}

// MARK: - AccessibilityPermission

final class AccessibilityPermission: Permission {
    init() {
        super.init(
            title: "辅助功能",
            details: [
                "获取菜单栏的实时信息。",
                "排列菜单栏项目。",
            ],
            isRequired: true,
            settingsURL: nil,
            check: {
                checkIsProcessTrusted()
            },
            request: {
                checkIsProcessTrusted(prompt: true)
            }
        )
    }
}

// MARK: - ScreenRecordingPermission

final class ScreenRecordingPermission: Permission {
    init() {
        super.init(
            title: "屏幕录制",
            details: [
                "编辑菜单栏的外观。",
                "显示各个菜单栏项目的图像。",
            ],
            isRequired: false,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            check: {
                ScreenCapture.checkPermissions()
            },
            request: {
                ScreenCapture.requestPermissions()
            }
        )
    }
}
