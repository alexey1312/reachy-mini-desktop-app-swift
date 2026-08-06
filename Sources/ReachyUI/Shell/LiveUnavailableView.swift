import SwiftUI

/// Why the viewport is empty. Both the geometry and the state stream sit behind
/// the robot's backend, so a connection alone shows nothing.
struct LiveUnavailableView: View {
    var body: some View {
        ContentUnavailableView(
            "No live view",
            systemImage: "cube.transparent",
            description: Text("Start the robot backend to see the model and the camera.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
