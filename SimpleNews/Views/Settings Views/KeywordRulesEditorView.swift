//
//  KeywordRulesEditorView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/23/26.
//

import SwiftUI

struct KeywordRulesEditorView: View {
    @State private var categories: [CategoryTagRules] = []

    var body: some View {
        NavigationView {
            List {
                ForEach(categories) { cat in
                    Section(header: Text(cat.category)) {
                        ForEach(cat.tags, id: \.tag) { rule in
                            ruleRow(category: cat.category, rule: rule)
                        }
                    }
                }
            }
            .navigationTitle("Keyword Tags")
            .onAppear(perform: reload)
        }
    }

    @ViewBuilder
    private func ruleRow(category: String, rule: TagRule) -> some View {
        HStack {
            Text(rule.tag)
                .font(.body)
            Spacer()
            Picker(
                "",
                selection: binding(
                    for: category,
                    tag: rule.tag,
                    current: rule.status
                )
            ) {
                Text("Y").tag(TagStatus.yes)
                Text("U").tag(TagStatus.undecided)
                Text("N").tag(TagStatus.no)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }

    private func reload() {
        categories = KeywordTagger.shared.allCategoryRules()
    }

    private func binding(
        for category: String,
        tag: String,
        current: TagStatus
    ) -> Binding<TagStatus> {
        Binding<TagStatus>(
            get: {
                if let cat = categories.first(where: { $0.category == category }),
                   let rule = cat.tags.first(where: { $0.tag == tag }) {
                    return rule.status
                }
                return current
            },
            set: { newStatus in
                KeywordTagger.shared.setStatus(
                    category: category,
                    tag: tag,
                    status: newStatus
                )
                reload()
            }
        )
    }
}

#if DEBUG
#Preview("Keyword Rules Editor") {
    NavigationStack {
        KeywordRulesEditorView()
    }
}
#endif
