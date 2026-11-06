import SwiftUI

/// The film-advance wheel. Drag it (either direction) until it stops; each notch clicks.
struct ThumbWheel: View {
    /// True when the camera needs winding. Once wound, the wheel locks like the real thing.
    let needsWind: Bool
    let onWound: () -> Void

    private let notchesToWind = 8
    private let notchSpacing: CGFloat = 14
    private let ridgePitch: CGFloat = 7

    @State private var notches = 0
    @State private var stepsInDrag = 0
    @State private var spin: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(white: 0.06), Color(white: 0.2), Color(white: 0.06)],
                                     startPoint: .leading, endPoint: .trailing))
            VStack(spacing: ridgePitch - 2) {
                ForEach(0..<44, id: \.self) { _ in
                    Capsule().fill(Color(white: 0.34)).frame(height: 2)
                }
            }
            .padding(.horizontal, 5)
            .offset(y: spin.truncatingRemainder(dividingBy: ridgePitch))
            LinearGradient(colors: [.black.opacity(0.75), .clear, .clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black, lineWidth: 2))
        .overlay(alignment: .bottom) {
            if needsWind {
                Capsule().fill(Color.orange)
                    .frame(width: 18, height: 4)
                    .offset(y: 10)
                    .opacity(Double(notchesToWind - notches) / Double(notchesToWind))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard needsWind else { return }
                    let steps = Int(abs(value.translation.height) / notchSpacing)
                    guard steps > stepsInDrag else { return }
                    for _ in stepsInDrag..<steps where notches < notchesToWind {
                        notches += 1
                        spin += value.translation.height >= 0 ? notchSpacing : -notchSpacing
                        Haptics.click()
                    }
                    stepsInDrag = steps
                    if notches >= notchesToWind {
                        Haptics.clunk()
                        notches = 0
                        onWound()
                    }
                }
                .onEnded { _ in stepsInDrag = 0 }
        )
        .onChange(of: needsWind) { _, newValue in
            if newValue { notches = 0 }
        }
        .accessibilityLabel("Film advance wheel")
        .accessibilityHint(needsWind ? "Wind the film before the next shot" : "Wound")
        .accessibilityAction { if needsWind { Haptics.clunk(); onWound() } }
    }
}
