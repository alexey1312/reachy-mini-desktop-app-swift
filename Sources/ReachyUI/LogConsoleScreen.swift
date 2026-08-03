import ReachyKit
import SwiftUI

/// Live daemon log console (journalctl tail over WebSocket).
struct LogConsoleScreen: View {
    let address: RobotAddress

    @State private var model = LogConsoleModel()
    @State private var setupError: String?
    @State private var atBottom = true
    @State private var jumpToken = 0
    @AppStorage("logConsole.capacity") private var capacity = 5000

    private enum Anchor: Hashable {
        case bottom
    }

    var body: some View {
        Group {
            if let setupError {
                ContentUnavailableView("Log stream failed", systemImage: "xmark.octagon", description: Text(setupError))
            } else if model.entries.isEmpty {
                ContentUnavailableView(
                    "Waiting for logs…",
                    systemImage: "text.alignleft",
                    description: Text("Daemon logs come from journalctl on the robot — the local simulator has none.")
                )
            } else if model.visible.isEmpty {
                ContentUnavailableView.search
            } else {
                logList
            }
        }
        .navigationTitle("Daemon logs")
        .safeAreaInset(edge: .bottom) { statusBar }
        .searchable(text: $model.query, prompt: "Filter log")
        .toolbar { toolbarContent }
        .task { await stream() }
        .onAppear { model.capacity = capacity }
        .onChange(of: capacity) { model.capacity = capacity }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(model.visible) { entry in
                    row(entry)
                }
                // iOS 17 has no scroll-position API; a zero-height sentinel is how the view
                // learns whether the user is still parked at the tail.
                Color.clear
                    .frame(height: 1)
                    .listRowSeparator(.hidden)
                    .id(Anchor.bottom)
                    .onAppear { atBottom = true }
                    .onDisappear { atBottom = false }
            }
            .listStyle(.plain)
            .onChange(of: model.visible.last?.id) {
                guard atBottom else { return }
                proxy.scrollTo(Anchor.bottom, anchor: .bottom)
            }
            .onChange(of: jumpToken) {
                withAnimation { proxy.scrollTo(Anchor.bottom, anchor: .bottom) }
                atBottom = true
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(statusText)
            Spacer()
            if !atBottom {
                Button("Jump to latest", systemImage: "arrow.down.to.line") { jumpToken += 1 }
                    .buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var statusText: String {
        var parts: [String] = []
        if model.isFiltered {
            parts.append("\(model.visible.count) of \(model.entries.count) lines")
        } else {
            parts.append("\(model.entries.count) lines")
        }
        if model.paused {
            parts.append(model.pending.isEmpty ? "paused" : "paused · +\(model.pending.count) new")
        }
        return parts.joined(separator: " · ")
    }

    private func row(_ entry: LogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let timestamp = entry.timestamp {
                Text(timestamp)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.message)
                .foregroundStyle(Self.color(for: entry.level))
        }
        .font(.caption2.monospaced())
        .textSelection(.enabled)
        .contextMenu {
            Button("Copy line", systemImage: "doc.on.doc") { Clipboard.copy(entry.text) }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(.init(top: 1, leading: 8, bottom: 1, trailing: 8))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play" : "pause") {
                model.paused.toggle()
            }
            ShareLink(item: model.export(address: address.displayString), preview: SharePreview("Daemon log")) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(model.visible.isEmpty)
            Menu {
                Picker("Level", selection: $model.minimumLevel) {
                    Text("All").tag(LogLevel.debug)
                    Text("Info and above").tag(LogLevel.info)
                    Text("Warnings and above").tag(LogLevel.warning)
                    Text("Errors").tag(LogLevel.error)
                }
                Picker("Buffer", selection: $capacity) {
                    ForEach(LogConsoleModel.capacities, id: \.self) { size in
                        Text("\(size) lines").tag(size)
                    }
                }
                Divider()
                Button("Copy all", systemImage: "doc.on.doc") { Clipboard.copy(model.copyText) }
                    .disabled(model.visible.isEmpty)
                Button("Clear", systemImage: "trash", role: .destructive) { model.clear() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private static func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: .secondary
        case .info: .primary
        case .warning: .orange
        case .error: .red
        }
    }

    /// `.task` cancels the stream when the screen goes away — no manual task handle.
    private func stream() async {
        do {
            let client = try LogStreamClient(address: address)
            for await chunk in client.lines() {
                model.ingest(chunk)
            }
        } catch {
            setupError = "\(error)"
        }
    }
}
