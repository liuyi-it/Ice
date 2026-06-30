//
//  BindingExposable.swift
//  Ice
//

import SwiftUI

/// 将其可写属性公开为绑定的类型。
protocol BindingExposable {
    /// 公开此类型可写属性绑定的镜头。
    typealias Bindings = ExposedBindings<Self>

    /// 公开此实例可写属性绑定的镜头。
    var bindings: Bindings { get }
}

extension BindingExposable {
    var bindings: Bindings {
        Bindings(base: self)
    }
}

/// 公开基础对象绑定的镜头。
@dynamicMemberLookup
struct ExposedBindings<Base: BindingExposable> {
    /// 公开绑定的对象。
    private let base: Base

    /// 创建公开给定对象绑定的镜头。
    init(base: Base) {
        self.base = base
    }

    /// 返回给定键路径属性的绑定。
    subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<Base, Value>) -> Binding<Value> {
        Binding(get: { base[keyPath: keyPath] }, set: { base[keyPath: keyPath] = $0 })
    }

    /// 返回公开给定键路径对象绑定的镜头。
    subscript<T: BindingExposable>(dynamicMember keyPath: KeyPath<Base, T>) -> ExposedBindings<T> {
        ExposedBindings<T>(base: base[keyPath: keyPath])
    }
}
