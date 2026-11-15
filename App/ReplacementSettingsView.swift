import HandyKit
import Observation
import SwiftUI

@MainActor @Observable
final class ReplacementSettingsModel {
    private(set) var rules: [ReplacementRule]
    var error: String?
    private let storage: any ReplacementRuleStorage

    init(storage: any ReplacementRuleStorage = UserDefaultsReplacementStorage.appDefault()) {
        self.storage = storage
        rules = storage.load()
    }

    func save(_ updated: [ReplacementRule]) {
        do {
            try storage.save(updated)
            rules = updated
        } catch {
            self.error = "Could not save replacements. Try again."
        }
    }
}

struct ReplacementSettingsView: View {
    @Bindable var model: ReplacementSettingsModel
    @State private var editing: ReplacementRule?
    @Environment(HandoffModel.self) private var handoff

    #if DEBUG
    var snapshotSheet = false
    #endif

    var body: some View {
        List {
            Section {
                ForEach(model.rules) { rule in
                    Button { editing = rule } label: {
                        HStack {
                            Text(rule.phrase)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text(rule.replacement)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Replace \(rule.phrase) with \(rule.replacement)")
                }
                .onDelete { offsets in
                    var rules = model.rules
                    rules.remove(atOffsets: offsets)
                    model.save(rules)
                }
                .onMove { offsets, destination in
                    var rules = model.rules
                    rules.move(fromOffsets: offsets, toOffset: destination)
                    model.save(rules)
                }
            } footer: {
                Text("Rules run from top to bottom after each dictation. Matches whole words and ignores case.")
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.rules.isEmpty {
                ContentUnavailableView {
                    Label("No Replacements", systemImage: "arrow.left.arrow.right")
                } description: {
                    Text("Add a rule to fix a name or term that dictation gets wrong.")
                } actions: {
                    Button("Add Rule") { addRule() }
                }
            }
        }
        .navigationTitle("Replacements")
        .onAppear {
            #if DEBUG
            if snapshotSheet { editing = model.rules.first ?? ReplacementRule(phrase: "", replacement: "") }
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Rule", systemImage: "plus") { addRule() }
            }
        }
        .sheet(item: $editing) { rule in
            ReplacementRuleEditor(model: model, rule: rule)
                .handoffPresenter(inSheet: true)
        }
        // #38: the editor has text fields, so it presents dictation while it is open.
        .onChange(of: editing != nil) { _, open in handoff.sheetOpen = open }
        .alert("Could Not Save", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private func addRule() { editing = ReplacementRule(phrase: "", replacement: "") }
}

private struct ReplacementRuleEditor: View {
    let model: ReplacementSettingsModel
    let rule: ReplacementRule
    @Environment(\.dismiss) private var dismiss
    @State private var phrase = ""
    @State private var replacement = ""
    @FocusState private var phraseFocused: Bool

    private var duplicate: Bool {
        PhraseReplacement.isDuplicate(phrase, in: model.rules, excluding: rule.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Replace") {
                        TextField("What dictation writes", text: $phrase).focused($phraseFocused)
                    }
                    if duplicate {
                        Text("A rule for this phrase already exists.").font(.footnote).foregroundStyle(.red)
                    }
                    LabeledContent("With") {
                        TextField("What you want", text: $replacement)
                    }
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle(model.rules.contains(where: { $0.id == rule.id }) ? "Edit Rule" : "New Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let updated = ReplacementRule(id: rule.id, phrase: phrase, replacement: replacement)
                        var rules = model.rules
                        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = updated }
                        else { rules.append(updated) }
                        model.save(rules)
                        if model.error == nil { dismiss() }
                    }
                    .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || duplicate)
                }
            }
            .onAppear {
                phrase = rule.phrase
                replacement = rule.replacement
                #if DEBUG
                phraseFocused = SnapshotState.requested == nil
                #else
                phraseFocused = true
                #endif
            }
        }
    }
}
