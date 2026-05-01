import AppKit
import SwiftUI

struct PRMenuView: View {
    private enum Layout {
        static let panelWidth: CGFloat = 480
        static let minPanelHeight: CGFloat = 220
        static let maxPanelHeight: CGFloat = 800
        static let inlineMessageHeight: CGFloat = 40
        static let sectionHeaderHeight: CGFloat = 34
        static let rowHeight: CGFloat = 31
        static let scrollPadding: CGFloat = 12
    }

    @ObservedObject var service: GitHubService
    @State private var staleExpanded = false
    @State private var slackCopied = false
    @State private var showUpdated = false
    @State private var marqueeStart: Date? = nil
    @State private var panelVisible = false

    private var grouped: [PRCategory: [PullRequest]] {
        let dict = Dictionary(grouping: service.pullRequests, by: \.category)
        return dict.mapValues { prs in
            prs.sorted { a, b in
                if a.repoName != b.repoName {
                    return a.repoName < b.repoName
                }
                return a.number > b.number
            }
        }
    }

    private var visibleCategories: [PRCategory] {
        PRCategory.allCases.filter { !(grouped[$0] ?? []).isEmpty }
    }

    private var visibleRowCount: Int {
        visibleCategories.reduce(into: 0) { count, category in
            guard let prs = grouped[category] else { return }
            if category == .stale, !staleExpanded {
                return
            }
            count += prs.count
        }
    }

    private var minimumPanelHeight: CGFloat {
        if service.pullRequests.isEmpty {
            return service.errorMessage == nil ? Layout.inlineMessageHeight : Layout.inlineMessageHeight * 1.2
        }
        return Layout.minPanelHeight
    }

    private var idealPanelHeight: CGFloat {
        if service.pullRequests.isEmpty {
            return minimumPanelHeight
        }

        let topMessageHeight = service.errorMessage == nil ? 0 : Layout.inlineMessageHeight
        let contentHeight =
            topMessageHeight +
            CGFloat(visibleCategories.count) * Layout.sectionHeaderHeight +
            CGFloat(visibleRowCount) * Layout.rowHeight +
            Layout.scrollPadding

        return min(max(contentHeight, minimumPanelHeight), Layout.maxPanelHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = service.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }

            if service.pullRequests.isEmpty && !service.isLoading && service.errorMessage == nil {
                Text("No open PRs")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(PRCategory.allCases, id: \.rawValue) { category in
                        if let prs = grouped[category], !prs.isEmpty {
                            if category == .stale {
                                staleSection(prs: prs)
                            } else {
                                sectionView(category: category, prs: prs)
                            }
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: Layout.panelWidth, alignment: .topLeading)
        .frame(
            minHeight: minimumPanelHeight,
            idealHeight: idealPanelHeight,
            maxHeight: Layout.maxPanelHeight,
            alignment: .topLeading
        )
        .overlay(alignment: .bottomTrailing) {
            if showUpdated, let date = service.lastRefreshed {
                Text("Updated \(date.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(6)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
            }
        }
        .onChange(of: service.lastRefreshed) {
            withAnimation(.easeOut(duration: 0.25)) {
                showUpdated = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeIn(duration: 0.4)) {
                    showUpdated = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await service.fetchPRs() }
            panelVisible = true
            marqueeStart = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                guard panelVisible else { return }
                marqueeStart = Date()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            panelVisible = false
            marqueeStart = nil
        }
        .contextMenu {
            Button("Refresh Now") {
                Task { await service.fetchPRs() }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private func sectionView(category: PRCategory, prs: [PullRequest]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(category.title.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                if category == .readyForReview {
                    copyForSlackButton(prs: prs)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(prs) { pr in
                prRow(pr)
            }
        }
    }

    @ViewBuilder
    private func copyForSlackButton(prs: [PullRequest]) -> some View {
        Button {
            let links = prs.map { "- \($0.url)" }.joined(separator: "\n")
            let message = "folks could you please look into these:\n\(links)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message, forType: .string)
            slackCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                slackCopied = false
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: slackCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 8, weight: .medium))
                Text(slackCopied ? "Copied!" : "Copy for Slack")
                    .font(.system(size: 9, weight: .medium))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(SlackCopyButtonStyle())
    }

    @ViewBuilder
    private func staleSection(prs: [PullRequest]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    staleExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("STALE")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(verbatim: "(\(prs.count))")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(staleExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if staleExpanded {
                ForEach(prs) { pr in
                    prRow(pr)
                }
            }
        }
    }

    @ViewBuilder
    private func prRow(_ pr: PullRequest) -> some View {
        Button {
            if let url = URL(string: pr.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: pr.checkStatus.icon)
                    .foregroundStyle(checkColor(pr.checkStatus).opacity(0.8))
                    .font(.system(size: 11))
                    .frame(width: 14)

                Text(pr.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 13))

                Spacer(minLength: 8)

                Text(verbatim: "#\(pr.number)")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11))

                MarqueeText(text: pr.repoName, startTime: marqueeStart)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }

    private func checkColor(_ status: CheckStatus) -> Color {
        switch status {
        case .success, .noChecks: .green
        case .failure: .red
        case .pending: .orange
        }
    }
}

struct MarqueeText: View {
    let text: String
    let startTime: Date?

    private static let columnWidth: CGFloat = 38
    private static let speed: Double = 15

    @State private var textWidth: CGFloat = 0

    private var overflow: CGFloat {
        max(0, textWidth - Self.columnWidth)
    }

    var body: some View {
        if let startTime, overflow > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
                let elapsed = context.date.timeIntervalSince(startTime)
                let cycleDuration = Double(overflow) / Self.speed
                let totalCycle = cycleDuration * 2
                let phase = elapsed.truncatingRemainder(dividingBy: totalCycle)
                let progress = phase < cycleDuration
                    ? phase / cycleDuration
                    : 1.0 - (phase - cycleDuration) / cycleDuration
                let eased = 0.5 - 0.5 * cos(progress * .pi)

                innerText(offset: -eased * overflow)
            }
        } else {
            innerText(offset: 0)
        }
    }

    private func innerText(offset: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.quaternary)
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: TextWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(TextWidthKey.self) { textWidth = $0 }
            .offset(x: offset)
            .frame(width: Self.columnWidth, alignment: .leading)
            .clipped()
    }
}

private struct TextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct SlackCopyButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered ? .secondary : .quaternary)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
