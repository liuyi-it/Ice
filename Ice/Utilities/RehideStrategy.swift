//
//  RehideStrategy.swift
//  Ice
//

import SwiftUI

/// 确定自动重新隐藏功能工作方式的类型。
enum RehideStrategy: Int, CaseIterable, Identifiable {
    /// 菜单栏项目使用智能算法重新隐藏。
    case smart = 0
    /// 菜单栏项目在给定时间间隔后重新隐藏。
    case timed = 1
    /// 菜单栏项目在聚焦的应用程序更改时重新隐藏。
    case focusedApp = 2

    var id: Int { rawValue }

    /// 本地化字符串键表示。
    var localized: LocalizedStringKey {
        switch self {
        case .smart: "智能"
        case .timed: "定时"
        case .focusedApp: "聚焦应用"
        }
    }
}
