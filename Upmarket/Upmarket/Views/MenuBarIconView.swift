import SwiftUI

struct MenuBarIconView: View {

    let isConverting: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let icon = NSImage(named: "MenuBarHash") {
                ZStack {
                    if isConverting {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 10, height: 10)
                            .offset(x: -1, y: -1)
                    }

                    Image(nsImage: icon)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Color.primary)
                }
            }

            if isConverting {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 22, height: 22)
    }
}
