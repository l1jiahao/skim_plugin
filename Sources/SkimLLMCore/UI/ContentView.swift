import SwiftUI

public struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var isNearBottom = true
    @State private var pendingScrollToBottom = false
    private let bottomID = "message-bottom"

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            inputBar
        }
        .background(
            WindowAccessor { window in
                model.attach(window: window)
            }
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
        }
        .sheet(isPresented: $showingHistory) {
            SessionHistoryView(model: model)
        }
        .onAppear {
            model.start()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.documentState?.title ?? "Waiting for Skim")
                        .font(.headline)
                        .lineLimit(1)
                    Text(documentSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if model.config.isDeepSeekOptimized {
                    ProviderBadge(preset: .deepSeek)
                        .help("DeepSeek mode")
                }

                Button {
                    showingHistory = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        if !model.sessionSummaries.isEmpty {
                            Text("\(model.sessionSummaries.count)")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.documentState == nil)
                .help("Paper chat history")

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }

            Text(model.indexState.label)
                .font(.caption)
                .foregroundStyle(indexColor)

            if model.config.isDeepSeekOptimized {
                Picker("DeepSeek mode", selection: deepSeekModeBinding) {
                    ForEach(DeepSeekInteractionMode.allCases, id: \.self) { mode in
                        Text(mode.shortLabel).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Fast uses deepseek-v4-flash with thinking off. Deep uses deepseek-v4-pro with thinking on.")
            }

            if let error = model.runtimeError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
    }

    private var deepSeekModeBinding: Binding<DeepSeekInteractionMode> {
        Binding(
            get: { model.config.deepSeekInteractionMode },
            set: { model.setDeepSeekInteractionMode($0) }
        )
    }

    private var documentSubtitle: String {
        guard let state = model.documentState else {
            return "Open a PDF in Skim"
        }
        let selection = state.selectedText.isEmpty ? "" : " · selection ready"
        return "Page \(state.currentPage) of \(state.pageCount)\(selection)"
    }

    private var indexColor: Color {
        switch model.indexState {
        case .failed:
            return .red
        case .ready:
            return .green
        case .noText:
            return .orange
        default:
            return .secondary
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if !model.lastContextChunks.isEmpty {
                            SourceStrip(chunks: model.lastContextChunks)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding(14)
                }
                .background(ScrollViewObserver(isNearBottom: $isNearBottom))

                if !isNearBottom {
                    Button {
                        pendingScrollToBottom = false
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Jump to latest message")
                    .padding(12)
                }
            }
            .onChange(of: model.messages.count) { _ in
                guard pendingScrollToBottom else { return }
                pendingScrollToBottom = false
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            ChatInputView(text: $model.draft) {
                submitDraft()
            }
                .frame(minHeight: 72, maxHeight: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )

            HStack {
                if model.config.isDeepSeekOptimized {
                    ContextUsageRing(snapshot: model.contextUsage)
                }

                Text(contextLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if model.isSending {
                    Button {
                        model.cancelSend()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .help("Cancel")
                }

                Button {
                    submitDraft()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(model.isSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send")

                Button {
                    model.startNewSession()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(model.isSending || model.documentState == nil)
                .help("Start new session")
            }

        }
        .padding(12)
    }

    private func submitDraft() {
        pendingScrollToBottom = true
        model.sendCurrentDraft()
    }

    private var contextLabel: String {
        if model.config.contextMode == .deepSeekLongContext {
            return "DeepSeek long context"
        }
        return model.config.useFullPDFWhenAvailable && model.config.supportsPDFInput ? "Full PDF enabled" : "RAG context"
    }
}

private struct ContextUsageRing: View {
    let snapshot: ContextUsageSnapshot
    private let size: CGFloat = 30
    private let lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(centerText)
                .font(.system(size: snapshot.hasUsage ? 9 : 12, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .help(helpText)
    }

    private var progress: Double {
        snapshot.hasUsage ? snapshot.usageRatio : 0
    }

    private var centerText: String {
        snapshot.hasUsage ? "\(snapshot.percent)" : "-"
    }

    private var helpText: String {
        "\(snapshot.displayText). \(snapshot.detailText)"
    }

    private var color: Color {
        if snapshot.isCritical {
            return .red
        }
        if snapshot.isWarning {
            return .orange
        }
        return .secondary
    }
}

private struct ProviderBadge: View {
    let preset: ProviderPreset

    var body: some View {
        switch preset {
        case .deepSeek:
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.12, green: 0.38, blue: 0.85))
                    Text("DS")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)

                Text("DeepSeek")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.14))
            )

        case .openAICompatible:
            EmptyView()
        }
    }
}

private struct SessionHistoryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Paper Chat History")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    model.startNewSession()
                    dismiss()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .disabled(model.documentState == nil)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding(14)

            Divider()

            if model.documentState == nil {
                HistoryEmptyState(
                    title: "No PDF Open",
                    systemImage: "doc",
                    description: "Open a paper in Skim to see its saved conversations."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.sessionSummaries.isEmpty {
                HistoryEmptyState(
                    title: "No Saved Sessions",
                    systemImage: "clock.arrow.circlepath",
                    description: "Ask a question to create the first saved session for this paper."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.sessionSummaries) { summary in
                            SessionHistoryRow(
                                summary: summary,
                                isActive: summary.id == model.activeSessionID,
                                open: {
                                    model.openSession(summary.id)
                                    dismiss()
                                },
                                delete: {
                                    model.deleteSession(summary.id)
                                }
                            )
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: 520, height: 560)
    }

    private var subtitle: String {
        guard let state = model.documentState else {
            return "No paper selected"
        }
        let count = model.sessionSummaries.count
        let turns = model.sessionSummaries.map(\.userMessageCount).reduce(0, +)
        return "\(state.title) · \(count) saved \(count == 1 ? "session" : "sessions") · \(turns) turns"
    }
}

private struct HistoryEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(24)
    }
}

private struct SessionHistoryRow: View {
    let summary: ChatSessionSummary
    let isActive: Bool
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if isActive {
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                Spacer()
            }

            Text(summary.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text("\(summary.userMessageCount) turns · \(summary.messageCount) messages")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(summary.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    open()
                } label: {
                    Label("Open", systemImage: "arrow.up.left.square")
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    delete()
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .help("Delete session")
            }
        }
        .padding(10)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
        )
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 28)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(message.role == .user ? "You" : "Assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if message.role == .assistant {
                    if !message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ReasoningDisclosure(text: message.reasoningContent)
                    }

                    MarkdownMessageView(text: message.content)
                        .textSelection(.enabled)
                } else {
                    MarkdownMessageView(text: message.content.isEmpty ? "Thinking..." : message.content)
                        .textSelection(.enabled)
                }
            }
            .padding(message.role == .assistant ? 12 : 10)
            .background(message.role == .user ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(message.role == .assistant ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 28)
            }
        }
    }
}

private struct ReasoningDisclosure: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                Text("Thinking")
                    .font(.caption.weight(.semibold))
                Text("\(text.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.purple.opacity(0.18))
        )
    }
}

private struct SourceStrip: View {
    let chunks: [PDFChunk]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chunks) { chunk in
                        Text("p. \(chunk.pageNumber)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}
