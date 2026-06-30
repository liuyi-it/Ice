//
//  NavigationIdentifier.swift
//  Ice
//

import SwiftUI

/// 表示用户界面导航标识符的协议
protocol NavigationIdentifier: CaseIterable, Hashable, Identifiable, RawRepresentable {
    /// 可展示给用户的本地化描述
    var localized: LocalizedStringKey { get }
}

extension NavigationIdentifier where ID == Int {
    var id: Int { hashValue }
}

extension NavigationIdentifier where RawValue == String {
    var localized: LocalizedStringKey { LocalizedStringKey(rawValue) }
}
