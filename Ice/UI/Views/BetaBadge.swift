//
//  BetaBadge.swift
//  Ice
//

import SwiftUI

/// A view that displays a badge indicating a beta feature.
struct BetaBadge: View {
    var body: some View {
        Text("测试版")
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .background {
                Capsule(style: .circular)
                    .stroke()
            }
            .foregroundStyle(.green)
    }
}
