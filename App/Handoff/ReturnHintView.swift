import SwiftUI

struct ReturnHintView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 56))
                .accessibilityHidden(true)
            Text("Go Back to Your App")
                .font(.title)
            Text("Tap ◀ in the top-left corner, or swipe right on the bottom edge of the screen.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

struct ReturnHintView_Previews: PreviewProvider {
    static var previews: some View {
        ReturnHintView()
        ReturnHintView().preferredColorScheme(.dark)
    }
}
