//
//  ImportURLView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import SwiftUI

struct ImportURLView: View {
    @EnvironmentObject var importedStore: ImportedArticlesStore
    @Environment(\.dismiss) private var dismiss

    @State private var urlText: String = ""
    @State private var titleOverride: String = ""
    @State private var isImporting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Article URL") {
                    TextField("https://example.com/article", text: $urlText)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section("Title (optional)") {
                    TextField("Leave blank to auto-detect", text: $titleOverride)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await importArticle() }
                    } label: {
                        if isImporting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Import Article")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                }
            }
            .navigationTitle("Import URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func importArticle() async {
        isImporting = true
        errorMessage = nil

        do {
            let overrideTitle = titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            let article = try await ManualImportService.importArticle(
                from: urlText.trimmingCharacters(in: .whitespacesAndNewlines),
                titleOverride: overrideTitle.isEmpty ? nil : overrideTitle
            )
            importedStore.add(article)
            dismiss()
        } catch {
            errorMessage = "Failed to import: \(error.localizedDescription)"
        }

        isImporting = false
    }
}

#if DEBUG
#Preview("Import URL") {
    PreviewWrapper {
        ImportURLView()
    }
}
#endif
