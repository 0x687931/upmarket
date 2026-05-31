import SwiftUI

struct OnboardingView: View {

    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0

    private var steps: [OnboardingStep] {[
        OnboardingStep(
            symbol: "#",
            title: L("onboarding.welcome.title"),
            subtitle: L("onboarding.welcome.subtitle"),
            detail: nil,
            primaryLabel: L("onboarding.button.start"),
            secondaryLabel: nil
        ),
        OnboardingStep(
            symbol: "arrow.down.doc",
            title: L("onboarding.drop.title"),
            subtitle: L("onboarding.drop.subtitle"),
            detail: L("onboarding.drop.detail"),
            primaryLabel: L("onboarding.button.next"),
            secondaryLabel: nil
        ),
        OnboardingStep(
            symbol: "cpu",
            title: L("onboarding.ai.title"),
            subtitle: L("onboarding.ai.subtitle"),
            detail: L("onboarding.ai.detail"),
            primaryLabel: L("onboarding.button.begin"),
            secondaryLabel: L("onboarding.button.later")
        ),
    ]}

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                stepContent
                Spacer()
                controls
            }
            .padding(32)
        }
        .frame(width: 480, height: 400)
    }

    private var stepContent: some View {
        let s = steps[step]
        return VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                Group {
                    if s.symbol == "#" {
                        Text("#")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: s.symbol)
                            .font(.system(size: 36, weight: .light))
                    }
                }
                .foregroundStyle(Color.accentColor)
            }
            .transition(.scale.combined(with: .opacity))

            VStack(spacing: 8) {
                Text(s.title)
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(s.subtitle)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = s.detail {
                    Text(detail)
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
        }
        .id(step)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.spring(duration: 0.4), value: step)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: i == step ? 8 : 6, height: i == step ? 8 : 6)
                        .animation(.spring(duration: 0.3), value: step)
                }
            }
            .padding(.bottom, 4)

            let s = steps[step]
            Button(s.primaryLabel) { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

            if let secondary = s.secondaryLabel {
                Button(secondary) { complete() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func advance() {
        if step < steps.count - 1 {
            withAnimation { step += 1 }
        } else {
            complete()
        }
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: "upmarket.onboardingComplete")
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            ShelfWindowController.shared.show()
        }
    }
}

struct OnboardingStep {
    let symbol: String
    let title: String
    let subtitle: String
    let detail: String?
    let primaryLabel: String
    let secondaryLabel: String?
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
