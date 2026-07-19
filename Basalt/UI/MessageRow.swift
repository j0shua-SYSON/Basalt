import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    let retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user { Spacer(minLength: 46) }
            if message.role == .assistant {
                assistantMark
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
                if let attachments = message.attachments, !attachments.isEmpty {
                    attachmentLabels(attachments)
                }

                if message.role == .assistant,
                   let reasoning = message.reasoning,
                   !reasoning.isEmpty {
                    DisclosureGroup {
                        Text(reasoning)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    } label: {
                        Label("Thinking", systemImage: "brain.head.profile")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BasaltTheme.mineral)
                    }
                    .padding(12)
                    .background(BasaltTheme.mineral.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                if message.text.isEmpty && isStreaming {
                    TokenStrataView(isActive: true, compact: true)
                        .frame(width: 108, height: 42)
                        .accessibilityLabel("Generating response")
                } else {
                    Text(markdownText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if message.role == .assistant,
                   let sources = message.sources,
                   !sources.isEmpty {
                    SourceStrip(sources: sources)
                }

                if message.role == .assistant && !message.text.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        if let retry {
                            Button(action: retry) {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(message.role == .user ? 14 : 0)
            .background {
                if message.role == .user {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.opacity(0.13))
                }
            }
            .frame(maxWidth: message.role == .user ? 620 : .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 12) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .accessibilityElement(children: .contain)
    }

    private var assistantMark: some View {
        Image(systemName: "cube.transparent")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BasaltTheme.lichen)
            .frame(width: 30, height: 30)
            .background(BasaltTheme.lichen.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }

    private var markdownText: AttributedString {
        (try? AttributedString(
            markdown: message.text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.text)
    }

    private func attachmentLabels(_ attachments: [MediaAttachment]) -> some View {
        HStack(spacing: 7) {
            ForEach(attachments) { attachment in
                Label(
                    attachment.displayName,
                    systemImage: attachment.kind == .image ? "photo" : "waveform"
                )
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: Capsule())
            }
        }
    }
}

private struct SourceStrip: View {
    let sources: [WebSource]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    Link(destination: source.url) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("[\(index + 1)]  \(source.host)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BasaltTheme.slate)
                            Text(source.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        .frame(width: 210, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityLabel("Web sources")
    }
}
