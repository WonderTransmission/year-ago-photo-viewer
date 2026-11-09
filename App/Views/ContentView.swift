import SwiftUI
import YearAgoCore

/// Placeholder main window. Replaced by the photo viewer in M2.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Hello")
                .font(.largeTitle)
            Text(CoreInfo.appName)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView()
}
