import SwiftUI

/// The console proper: tailing list, level filter, search, pause, copy and export.
///
/// It owns no transport. The daemon journal arrives over a WebSocket, an update job
/// log over a different one, and the BLE recovery journal over GATT polling — all
/// three only have to push text into a `LogConsoleModel`.
struct LogConsoleView: View {
    /// `@Bindable`, not `let`: the search field and the level picker write back into
    /// the model the caller owns.
    @Bindable var model: LogConsoleModel
    /// Names the source in the exported file and the share sheet.
    let source: String
    /// Shown while nothing has arrived yet; each source is quiet for its own reason.
    let emptyDescription: String
    /// Set once the source has given up. Replaces the list — a frozen tail with no
    /// explanation reads as "no output" rather than "the feed died".
    var failure: String?

    @State private var atBottom = true
    @State private var jumpToken = 0
    @AppStorage("logConsole.capacity") private var capacity = 5000

    private enum Anchor: Hashable {
        case bottom
    }

    var body: some View {
        Group {
            if let failure {
                ContentUnavailableView("Log stream failed", systemImage: "xmark.octagon", description: Text(failure))
            } else if model.entries.isEmpty {
                ContentUnavailableView(
                    "Waiting for logs…",
                    systemImage: "text.alignleft",
                    description: Text(emptyDescription)
                )
            } else if model.visible.isEmpty {
                ContentUnavailableView.search
            } else {
                logList
            }
        }
        .safeAreaInset(edge: .bottom) { statusBar }
        .searchable(text: $model.query, prompt: "Filter log")
        .toolbar { toolbarContent }
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
            ShareLink(item: model.export(address: source), preview: SharePreview("Log")) {
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
}
