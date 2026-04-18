import SwiftUI

/// Phase 6 "Merged N duplicates" toast (UI-SPEC Component Inventory + Interaction Patterns).
///
/// Top-attached capsule with a 3-second auto-dismiss. Transition is reduce-motion
/// aware: when `accessibilityReduceMotion` is ON, uses a straight opacity fade;
/// otherwise slides in from the top combined with opacity.
///
/// Callers bind a `Bool` to `isPresented` and flip it to true when they want the
/// toast shown. The overlay self-dismisses after 3 seconds via `withAnimation`.
struct TransientToastOverlay: View {
    let message: String
    let icon: String
    let iconColor: Color
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isPresented {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(iconColor)
                    Text(message).font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .padding(.horizontal, 16)
                .transition(reduceMotion
                    ? AnyTransition.opacity
                    : AnyTransition.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel(message)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation { isPresented = false }
                    }
                }
            }
        }
    }
}
