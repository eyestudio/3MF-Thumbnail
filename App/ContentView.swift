import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("3MF Thumbnail")
                .font(.title)
                .fontWeight(.semibold)

            Text("Provides Finder thumbnails and Quick Look preview for .3mf files.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                Label("3MF file thumbnails in Finder", systemImage: "photo")
                Label("Press Space to preview 3D models", systemImage: "eye")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Text("Keep this app in the Applications folder for the extension to work.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Text("v\(BuildInfo.version)  Build: \(BuildInfo.buildTime)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(width: 420)
    }
}

#Preview {
    ContentView()
}
