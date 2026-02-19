//
//  ReaderController.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/18/26.
//

import Foundation
import WebKit

@MainActor
final class ReaderController: ObservableObject {
    weak var webView: WKWebView?
    @Published var isLoaded: Bool = false
}
