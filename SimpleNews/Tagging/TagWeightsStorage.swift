//
//  TagWeightsStorage.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import Foundation

private let tagWeightsKey = "tagWeights"

struct TagWeightsStorage {
    static func load() -> [String: Double] {
        if let dict = UserDefaults.standard.dictionary(forKey: tagWeightsKey) as? [String: Double] {
            return dict
        }
        return [:]
    }

    static func save(_ dict: [String: Double]) {
        UserDefaults.standard.set(dict, forKey: tagWeightsKey)
    }
}
