//
//  MenuBarTintKind.swift
//  Ice
//

import SwiftUI

/// 菜单栏着色类型
enum MenuBarTintKind: Int, CaseIterable, Codable, Identifiable {
    /// 不着色
    case none = 0
    /// 纯色
    case solid = 1
    /// 渐变
    case gradient = 2

    var id: Int { rawValue }

    /// 本地化字符串表示
    var localized: LocalizedStringKey {
        switch self {
        case .none: "无"
        case .solid: "纯色"
        case .gradient: "渐变"
        }
    }
}
