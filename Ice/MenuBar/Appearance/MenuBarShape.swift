//
//  MenuBarShape.swift
//  Ice
//

import CoreGraphics

/// 菜单栏形状端帽
enum MenuBarEndCap: Int, Codable, Hashable, CaseIterable {
    /// 方形端帽
    case square = 0
    /// 圆形端帽
    case round = 1
}

/// 菜单栏自定义形状类型
enum MenuBarShapeKind: Int, Codable, Hashable, CaseIterable {
    /// 不使用自定义形状
    case none = 0
    /// 全菜单栏形状
    case full = 1
    /// 分割式菜单栏形状
    case split = 2
}

/// 全菜单栏形状配置信息
struct MenuBarFullShapeInfo: Codable, Hashable {
    /// 左侧端帽
    var leadingEndCap: MenuBarEndCap
    /// 右侧端帽
    var trailingEndCap: MenuBarEndCap
}

extension MenuBarFullShapeInfo {
    var hasRoundedShape: Bool {
        leadingEndCap == .round || trailingEndCap == .round
    }
}

extension MenuBarFullShapeInfo {
    static let `default` = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
}

/// 分割式菜单栏形状配置信息
struct MenuBarSplitShapeInfo: Codable, Hashable {
    /// 左侧配置
    var leading: MenuBarFullShapeInfo
    /// 右侧配置
    var trailing: MenuBarFullShapeInfo
}

extension MenuBarSplitShapeInfo {
    var hasRoundedShape: Bool {
        leading.hasRoundedShape || trailing.hasRoundedShape
    }
}

extension MenuBarSplitShapeInfo {
    static let `default` = MenuBarSplitShapeInfo(leading: .default, trailing: .default)
}
