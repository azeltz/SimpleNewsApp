//
//  SubscriptionsView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/18/26.
//

import SwiftUI

struct SubscriptionsView: View {
    @ObservedObject private var store = SubscriptionStore.shared

    @State private var loginSource: SubscriptionSource?
    @State private var showAddSheet = false
    @State private var signOutSource: SubscriptionSource?

    var body: some View {
        List {
            Section("Built-in Sources") {
                ForEach(store.builtInSources) { source in
                    sourceRow(source)
                }
            }

            Section("My Sources") {
                if store.customSources.isEmpty {
                    Text("No custom sources. Tap + to add a paywalled site.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.customSources) { source in
                        sourceRow(source)
                    }
                    .onDelete(perform: deleteCustomSources)
                }
            }

            Section {
                Text("Sign in to paywalled news sources once and your session persists on this device. Nothing is sent to any server.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Subscriptions")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $loginSource) { source in
            SubscriptionLoginView(source: source, store: store)
        }
        .sheet(isPresented: $showAddSheet) {
            AddSubscriptionSourceView(store: store)
        }
        .confirmationDialog(
            "Sign out of \(signOutSource?.displayName ?? "")?",
            isPresented: Binding(
                get: { signOutSource != nil },
                set: { if !$0 { signOutSource = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                if let source = signOutSource {
                    Task { await store.logout(from: source) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await store.refreshAllLoginStatuses()
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func sourceRow(_ source: SubscriptionSource) -> some View {
        Button {
            if store.isLoggedIn(for: source) {
                signOutSource = source
            } else {
                loginSource = source
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.displayName)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(source.domain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if store.isLoggedIn(for: source) {
                    Text("Connected")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                } else {
                    Text("Not signed in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func deleteCustomSources(at offsets: IndexSet) {
        for index in offsets {
            store.removeCustomSource(store.customSources[index])
        }
    }
}

// MARK: - Add custom source sheet

private struct AddSubscriptionSourceView: View {
    @ObservedObject var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    @State private var domain = ""
    @State private var displayName = ""
    @State private var loginURLString = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Source details") {
                    TextField("Domain (e.g. theathletic.com)", text: $domain)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Display name", text: $displayName)

                    TextField("Login URL", text: $loginURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Text("Enter the domain and login page URL for a paywalled site you subscribe to.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addSource() }
                }
            }
        }
    }

    private func addSource() {
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = loginURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDomain.isEmpty else {
            errorMessage = "Please enter a domain."
            return
        }
        guard !trimmedURL.isEmpty, let loginURL = URL(string: trimmedURL) else {
            errorMessage = "Please enter a valid login URL."
            return
        }
        guard !store.hasSource(for: trimmedDomain) else {
            errorMessage = "This domain is already added."
            return
        }

        let name = trimmedName.isEmpty ? trimmedDomain : trimmedName
        store.addCustomSource(domain: trimmedDomain, displayName: name, loginURL: loginURL)
        dismiss()
    }
}

#if DEBUG
#Preview("Subscriptions") {
    NavigationStack {
        SubscriptionsView()
    }
}
#endif
