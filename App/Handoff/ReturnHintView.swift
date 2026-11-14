import SwiftUI

struct ReturnHintView: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 24) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: compact ? 24 : 56))
                .accessibilityHidden(true)
            Text("Go Back to Your App")
                .font(compact ? .headline : .title)
            Text("Tap ◀ in the top-left corner, or swipe right on the bottom edge of the screen.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(compact ? 8 : 32)
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity)
        .background(.background)
    }
}

struct ReturnHintView_Previews: PreviewProvider {
    static var previews: some View {
        ReturnHintView()
        ReturnHintView().preferredColorScheme(.dark)
    }
}
