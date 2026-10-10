//
//  IceSlider.swift
//  Ice
//

import CompactSlider
import SwiftUI

struct IceSlider<Value: BinaryFloatingPoint, ValueLabel: View, ValueLabelSelectability: TextSelectability>: View {
    private let value: Binding<Value>
    private let bounds: ClosedRange<Value>
    private let step: Value
    private let valueLabel: ValueLabel
    private let valueLabelSelectability: ValueLabelSelectability

    init(
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        step: Value = 0,
        valueLabelSelectability: ValueLabelSelectability = .disabled,
        @ViewBuilder valueLabel: () -> ValueLabel
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = valueLabel()
        self.valueLabelSelectability = valueLabelSelectability
    }

    init(
        _ valueLabelKey: LocalizedStringKey,
        valueLabelSelectability: ValueLabelSelectability = .disabled,
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        step: Value = 0
    ) where ValueLabel == Text {
        self.init(
            value: value,
            in: bounds,
            step: step,
            valueLabelSelectability: valueLabelSelectability
        ) {
            Text(valueLabelKey)
        }
    }

    var body: some View {
        CompactSlider(
            value: value,
            in: bounds,
            step: step
        )
        .compactSliderStyle(IceSliderStyle())
        .compactSliderHandleStyle(.rectangle(color: .primary, width: 1))
        .compactSliderScaleView(visibility: .always) { configuration in
            HStack {
                valueLabel
                    .textSelection(valueLabelSelectability)
            }
            .padding(.horizontal, 6)
            .foregroundStyle(.primary.opacity(configuration.focusState.isFocused ? 1 : 0.7))
        }
        .compactSliderOptionsByRemoving(.enabledHapticFeedback)
        .frame(height: 24)
    }
}

private struct IceSliderStyle: CompactSliderStyle {
    private let style = DefaultCompactSliderStyle.horizontal()

    var type: CompactSliderType { style.type }
    var padding: EdgeInsets { style.padding }

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        // SwiftUI measures settings rows at zero width before laying them out.
        // CompactSlider subtracts the handle width when sizing its progress;
        // only render its components once there is room for the one-point handle.
        if configuration.size.width >= 1 {
            style.makeBody(configuration: configuration)
        } else {
            Color.clear
        }
    }
}
