//
//  IceSliderTests.swift
//  Ice
//

import Cocoa
import SwiftUI

@MainActor
private final class SliderValue: ObservableObject {
    @Published var value = 1.0
}

private struct SliderFixture: View {
    @ObservedObject var model: SliderValue
    let colorScheme: ColorScheme
    var width: CGFloat = 240

    var body: some View {
        IceSlider(value: $model.value, in: 0...30, step: 1) {
            Text("Delay \(model.value.formatted())")
        }
        .frame(width: width)
        .environment(\.colorScheme, colorScheme)
    }
}

@main
private enum IceSliderTests {
    @MainActor
    static func snapshot<V: View>(_ host: NSHostingView<V>) -> Data {
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            fatalError("Slider cannot render")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.tiffRepresentation else {
            fatalError("Slider snapshot is unavailable")
        }
        return data
    }

    static func check(_ condition: Bool, _ name: String) {
        guard condition else {
            print("FAIL: \(name)")
            exit(EXIT_FAILURE)
        }
        print("PASS: \(name)")
    }

    @MainActor
    static func main() {
        _ = NSApplication.shared
        for scheme in [ColorScheme.light, .dark] {
            let model = SliderValue()
            let host = NSHostingView(rootView: SliderFixture(model: model, colorScheme: scheme))
            host.frame = CGRect(x: 0, y: 0, width: 240, height: 24)
            check(host.fittingSize.height == 24, "\(scheme) slider retains its compact height")
            let before = snapshot(host)
            model.value = 10
            RunLoop.current.run(until: .now.addingTimeInterval(0.2))
            let after = snapshot(host)
            check(before != after, "\(scheme) slider redraws when its bound value changes")
        }
        let model = SliderValue()
        let zeroWidthHost = NSHostingView(rootView: SliderFixture(model: model, colorScheme: .light, width: 0))
        zeroWidthHost.frame = CGRect(x: 0, y: 0, width: 0, height: 24)
        zeroWidthHost.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        zeroWidthHost.rootView = SliderFixture(model: model, colorScheme: .light)
        zeroWidthHost.frame = CGRect(x: 0, y: 0, width: 240, height: 24)
        check(!snapshot(zeroWidthHost).isEmpty, "zero-width measurement transitions to a rendered slider")

        let host = NSHostingView(rootView: IceSlider(
            "Spacing",
            valueLabelSelectability: .enabled,
            value: .constant(Float(0)),
            in: -16...16,
            step: 2
        ).disabled(true).frame(width: 240))
        host.frame = CGRect(x: 0, y: 0, width: 240, height: 24)
        check(!snapshot(host).isEmpty, "disabled Float slider with selectable label renders")
    }
}
