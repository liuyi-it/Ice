//
//  PermissionsManager.swift
//  Ice
//

import Combine
import Foundation

/// A type that manages the permissions of the app.
@MainActor
final class PermissionsManager: ObservableObject {
    /// The state of the granted permissions for the app.
    enum PermissionsState {
        case missingPermissions
        case hasAllPermissions
        case hasRequiredPermissions
    }

    /// The state of the granted permissions for the app.
    @Published var permissionsState = PermissionsState.missingPermissions

    let accessibilityPermission: AccessibilityPermission

    let screenRecordingPermission: ScreenRecordingPermission

    let allPermissions: [Permission]

    private(set) weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    /// A low-frequency timer that detects permissions being revoked while the
    /// app runs in the background.
    ///
    /// A menu bar app is rarely "become active", so the only re-check after
    /// `stopAllChecks()` would otherwise be `applicationDidBecomeActive`. If
    /// the user revokes a permission in System Settings while Ice is idle, the
    /// stale "has permissions" state would silently leave dependent features
    /// broken.
    private var revocationCheckCancellable: AnyCancellable?

    var requiredPermissions: [Permission] {
        allPermissions.filter { $0.isRequired }
    }

    init(appState: AppState) {
        self.appState = appState
        self.accessibilityPermission = AccessibilityPermission()
        self.screenRecordingPermission = ScreenRecordingPermission()
        self.allPermissions = [
            accessibilityPermission,
            screenRecordingPermission,
        ]
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        Publishers.Merge(
            accessibilityPermission.$hasPermission.mapToVoid(),
            screenRecordingPermission.$hasPermission.mapToVoid()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else {
                return
            }
            if allPermissions.allSatisfy({ $0.hasPermission }) {
                permissionsState = .hasAllPermissions
            } else if requiredPermissions.allSatisfy({ $0.hasPermission }) {
                permissionsState = .hasRequiredPermissions
            } else {
                permissionsState = .missingPermissions
            }
        }
        .store(in: &c)

        cancellables = c
    }

    /// Stops running all permissions checks.
    func stopAllChecks() {
        for permission in allPermissions {
            permission.stopCheck()
        }
    }

    /// Starts periodic permission revocation checks.
    ///
    /// Called after setup, once the app is running. Unlike the one-second
    /// polling used while waiting for permissions to be granted, this only
    /// refreshes the state; it does not interrupt the user.
    func startRevocationChecks() {
        revocationCheckCancellable?.cancel()
        revocationCheckCancellable = Timer.publish(every: 5, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshPermissions()
            }
    }

    /// Refreshes the current permissions state.
    func refreshPermissions() {
        for permission in allPermissions {
            permission.refresh()
        }
    }
}
