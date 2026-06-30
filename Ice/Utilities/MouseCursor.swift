//
//  MouseCursor.swift
//  Ice
//

import CoreGraphics

/// 鼠标光标操作的命名空间。
enum MouseCursor {
    /// 返回鼠标光标在 AppKit 框架坐标系中的位置，原点位于屏幕左下角。
    static var locationAppKit: CGPoint? {
        CGEvent(source: nil)?.unflippedLocation
    }

    /// 返回鼠标光标在 CoreGraphics 框架坐标系中的位置，原点位于屏幕左上角。
    static var locationCoreGraphics: CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// 隐藏鼠标光标并增加隐藏光标计数。
    static func hide() {
        let result = CGDisplayHideCursor(CGMainDisplayID())
        if result != .success {
            Logger.mouseCursor.error("CGDisplayHideCursor failed with error \(result.logString)")
        }
    }

    /// 减少隐藏光标计数，如果计数为 0 则显示鼠标光标。
    static func show() {
        let result = CGDisplayShowCursor(CGMainDisplayID())
        if result != .success {
            Logger.mouseCursor.error("CGDisplayShowCursor failed with error \(result.logString)")
        }
    }

    /// 在不生成事件的情况下将鼠标光标移动到指定点。
    ///
    /// - Parameter point: 全局显示坐标中移动光标的目标点。
    static func warp(to point: CGPoint) {
        let result = CGWarpMouseCursorPosition(point)
        if result != .success {
            Logger.mouseCursor.error("CGWarpMouseCursorPosition failed with error \(result.logString)")
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let mouseCursor = Logger(category: "MouseCursor")
}
