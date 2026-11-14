import HandyKit
import SwiftUI
import UIKit

/// Read the shared slot on resume and while Home is visible. No audio is retained here.
struct LastResultView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: DictationSession?
    @State private var result: LastResult?
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var limitedHeight: CGFloat = 0
    @State private var copied = false
    @State private var copyFeedbackID: UUID?
    @State private var discardTarget: LastResult?
    @State private var showDiscard = false
    @State private var storageError: String?

    var body: some View {
        Group {
            if let result {
                Section("Last Dictation") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.text)
                                .font(.body)
                                .lineLimit(expanded ? nil : 6)
                                .textSelection(.enabled)
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in
                                            if !expanded && fullHeight > limitedHeight + 1 { limitedHeight = height }
                                        }
                                    }
                                }
                                .background {
                                    Text(result.text).font(.body).fixedSize(horizontal: false, vertical: true)
                                        .background {
                                            GeometryReader { geometry in
                                                Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in
                                                    fullHeight = height
                                                }
                                            }
                                        }
                                        .hidden()
                                }
                            (Text("Expires in ") + Text(result.expiresAt, style: .relative))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("Last dictation, \(result.text), expires in ") + Text(result.expiresAt, style: .relative))
                        if !expanded && fullHeight > limitedHeight + 1 {
                            Button("Show All") { expanded = true }
                        }
                        HStack {
                            Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                                copy(result)
                            }
                            .buttonStyle(.bordered)
                            Button("Discard", systemImage: "trash") {
                                discardTarget = result
                                showDiscard = true
                            }
                            .buttonStyle(.bordered).tint(.red)
                        }
                    }
                }
            }
        }
        .confirmationDialog("Discard this text?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                guard let target = discardTarget else { return }
                do {
                    // A ready result uses acknowledgement, never TranscriptionFlow.cancel().
                    _ = try session?.discardResult(id: target.id)
                    refresh()
                } catch { storageError = "Could not discard this text. Try again." }
                discardTarget = nil
            }
            Button("Cancel", role: .cancel) { discardTarget = nil }
        }
        .alert("Could Not Read or Change Last Dictation", isPresented: Binding(
            get: { storageError != nil }, set: { if !$0 { storageError = nil } }
        )) {
            Button("OK") { storageError = nil }
        } message: { Text(storageError ?? "") }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            repeat {
                refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            } while !Task.isCancelled
        }
        .task(id: copyFeedbackID) {
            guard copyFeedbackID != nil else { return }
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            copied = false
        }
    }

    private func refresh() {
        do {
            if session == nil { session = DictationSession(storage: try AppGroupSessionStorage()) }
            let latest = try session?.lastResult()
            if latest?.id != result?.id {
                expanded = false
                copied = false
                copyFeedbackID = nil
            }
            result = latest
        } catch {
            result = nil
            storageError = "Could not read the last dictation. Try again."
        }
    }

    private func copy(_ displayed: LastResult) {
        do {
            // Check expiry and identity again before an explicit clipboard write.
            guard let latest = try session?.lastResult(), latest.id == displayed.id else {
                refresh()
                return
            }
            UIPasteboard.general.string = latest.text
            copied = true
            copyFeedbackID = UUID()
            UIAccessibility.post(notification: .announcement, argument: "Copied")
        } catch { storageError = "Could not copy this text. Try again." }
    }
}
