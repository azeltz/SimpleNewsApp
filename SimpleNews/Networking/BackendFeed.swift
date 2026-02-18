//
//  BackendFeed.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/17/26.
//

import Foundation

struct BackendFeed: Identifiable, Codable {
    let id: String
    let url: String
    let source: String
    let kind: String
    let schedule: Schedule?

    struct Schedule: Codable {
        let minutes: Int?
        let timeUTC: String?
    }
}
