import ReachyKit
import SwiftUI

/// Live daemon log console (journalctl tail over WebSocket).
struct LogConsoleScreen: View {
    let address: RobotAddress

    private static let maxLines = 2000

    @State private var lines: [Line] = []
    @State private var paused = false
    @State private var streamTask: Task<Void, Never>?
    @State private var setupError: String?

    private struct Line: Identifiable {
        let id: Int
        let text: String
    }

    var body: some View {
        Group {
            if let setupError {
                ContentUnavailableView("Log stream failed", systemImage: "xmark.octagon", description: Text(setupError))
            } else if lines.isEmpty {
                ContentUnavailableView(
                    "Waiting for logs…",
                    systemImage: "text.alignleft",
                    description: Text("Daemon logs come from journalctl on the robot — the local simulator has none.")
                )
            } else {
                logList
            }
        }
        .navigationTitle("Daemon logs")
        .toolbar {
            Button(paused ? "Resume" : "Pause") { paused.toggle() }
            Button("Clear", role: .destructive) { lines = [] }
        }
        .onAppear { start() }
        .onDisappear { streamTask?.cancel() }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List(lines) { line in
                Text(line.text)
                    .font(.caption2.monospaced())
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init(top: 1, leading: 8, bottom: 1, trailing: 8))
                    .id(line.id)
            }
            .listStyle(.plain)
            .onChange(of: lines.last?.id) {
                if !paused, let last = lines.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func start() {
        streamTask?.cancel()
        do {
            let client = try LogStreamClient(address: address)
            streamTask = Task {
                var nextID = 0
                for await text in client.lines() {
                    if paused {
                        continue
                    }
                    for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
                        lines.append(Line(id: nextID, text: String(raw)))
                        nextID += 1
                    }
                    if lines.count > Self.maxLines {
                        lines.removeFirst(lines.count - Self.maxLines)
                    }
                }
            }
        } catch {
            setupError = "\(error)"
        }
    }
}
