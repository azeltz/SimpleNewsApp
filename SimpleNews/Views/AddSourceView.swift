//
//  AddSourceView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/17/26.
//

import SwiftUI

struct AddSourceView: View {
    @State private var feedId: String = ""
    @State private var feedURL: String = ""
    @State private var feedSource: String = ""
    @State private var selectedKind: String = "periodic"

    @State private var isCustomKind = false
    @State private var customKindName = ""
    @State private var customHour = 12
    @State private var customMinute = 0

    @State private var statusMessage: String?

    // These must match the keys in INTERVALS in worker.js
    private let predefinedKinds = [
        "breaking",
        "critical",
        "top",
        "important",
        "consistent",
        "periodic",
        "social",
        "morning_daily"
    ]

    var body: some View {
        Form {
            Section(header: Text("New RSS Source")) {
                TextField("ID (e.g. user_custom_1)", text: $feedId)
                    .autocapitalization(.none)

                TextField("Feed URL", text: $feedURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)

                TextField("Source domain (e.g. example.com)", text: $feedSource)
                    .autocapitalization(.none)
            }

            Section(header: Text("Schedule kind")) {
                Toggle("Use custom schedule", isOn: $isCustomKind)

                if isCustomKind {
                    TextField("Custom kind name (e.g. morning_7am)", text: $customKindName)
                        .autocapitalization(.none)

                    Stepper("Hour (UTC): \(customHour)", value: $customHour, in: 0...23)
                    Stepper("Minute (UTC): \(customMinute)", value: $customMinute, in: 0...59)
                } else {
                    Picker("Kind", selection: $selectedKind) {
                        ForEach(predefinedKinds, id: \.self) { kind in
                            Text(kind)
                        }
                    }
                }
            }

            Section {
                Button("Add Source to Backend") {
                    Task {
                        await addSource()
                    }
                }
            }

            if let status = statusMessage {
                Section {
                    Text(status)
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Add Source")
    }

    private func addSource() async {
        guard
            !feedId.isEmpty,
            let url = URL(string: feedURL),
            !feedSource.isEmpty
        else {
            await MainActor.run {
                statusMessage = "Please fill all fields with valid values."
            }
            return
        }

        let kindToSend: String
        var schedule: [String: Any]? = nil

        if isCustomKind, !customKindName.isEmpty {
            kindToSend = customKindName
            let timeUTC = String(format: "%02d:%02d", customHour, customMinute)
            schedule = ["timeUTC": timeUTC]
        } else {
            kindToSend = selectedKind
        }

        let workerURL = URL(string: "https://rss-aggregator.simplenews.workers.dev/feeds")!
        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var feedDict: [String: Any] = [
            "id": feedId,
            "url": url.absoluteString,
            "source": feedSource,
            "kind": kindToSend,
        ]
        if let schedule = schedule {
            feedDict["schedule"] = schedule
        }

        let payload: [String: Any] = [
            "feeds": [feedDict]
        ]

        do {
            let body = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                await MainActor.run {
                    statusMessage = "Bad response from server."
                }
                return
            }

            guard (200...299).contains(http.statusCode) else {
                await MainActor.run {
                    statusMessage = "Server error \(http.statusCode)"
                }
                return
            }

            if
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let ok = json["ok"] as? Bool,
                ok == true
            {
                await MainActor.run {
                    statusMessage = "Source added successfully."
                }
            } else {
                await MainActor.run {
                    statusMessage = "Unexpected response from server."
                }
            }
        } catch {
            await MainActor.run {
                statusMessage = "Network error: \(error.localizedDescription)"
            }
        }
    }
}
