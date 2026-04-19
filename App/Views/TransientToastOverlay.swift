import SwiftUI

/// Phase 6 "Merged N duplicates" toast (UI-SPEC Component Inventory + Interaction Patterns).
///
/// Top-attached capsule with an auto-dismiss after `duration` seconds (default 3.0).
/// Transition is reduce-motion aware: when `accessibilityReduceMotion` is ON, uses a
/// straight opacity fade; otherwise slides in from the top combined with opacity.
///
/// Callers bind a `Bool` to `isPresented` and flip it to true when they want the
/// toast shown. The overlay self-dismisses after `duration` seconds via `withAnimation`.
///
/// Phase 7 note (FIDO-12): `duration` is parameterized so the silent-send toast can
/// fire for 2.0s per CONTEXT D-09 + UI-SPEC §Interaction Patterns. The default of 3.0s
/// preserves source-compatibility with every Phase 6 caller (none in production today;
/// the component was authored in Plan 06-06 but never mounted).
struct TransientToastOverlay: View {
    let message: String
    let icon: String
    let iconColor: Color
    let duration: Double
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        message: String,
        icon: String,
        iconColor: Color,
        duration: Double = 3.0,
        isPresented: Binding<Bool>
    ) {
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.duration = duration
        self._isPresented = isPresented
    }

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
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        withAnimation { isPresented = false }
                    }
                }
            }
        }
    }
}
