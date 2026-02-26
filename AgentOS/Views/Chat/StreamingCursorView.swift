import SwiftUI

struct StreamingCursorView: View {
    @State private var visible = true

    var body: some View {
        Text("|")
            .font(.system(size: 15, weight: .medium, design: .monospaced))
            .foregroundStyle(AppTheme.primary)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
