//
//  TwitterAccountsView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/16/26.
//

import SwiftUI

struct TwitterAccountsView: View {
    @StateObject private var viewModel = TwitterAccountsViewModel()
    @State private var newHandle: String = ""

    var body: some View {
        Form {
            Section("Followed accounts") {
                if viewModel.isLoading && viewModel.accounts.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                } else if let error = viewModel.errorMessage, viewModel.accounts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await viewModel.loadAccounts() }
                        }
                        .font(.footnote)
                    }
                } else if viewModel.accounts.isEmpty {
                    Text("No accounts yet. Add a handle below to get started.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.accounts, id: \.self) { account in
                        HStack {
                            Text("@\(account)")
                            Spacer()
                        }
                    }
                    .onDelete(perform: viewModel.removeAccounts)
                }
            }

            Section("Add account") {
                HStack {
                    TextField("Handle (e.g. ESPN)", text: $newHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Add") {
                        viewModel.addAccount(newHandle)
                        newHandle = ""
                    }
                    .disabled(newHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("Enter a Twitter/X handle without the @ symbol. Duplicates are ignored.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("X Accounts")
        .task {
            await viewModel.loadAccounts()
        }
    }
}

#if DEBUG
#Preview("Twitter Accounts") {
    PreviewWrapper {
        NavigationStack {
            TwitterAccountsView()
        }
    }
}
#endif
