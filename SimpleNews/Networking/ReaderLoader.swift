//
//  ReaderLoader.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/17/26.
//

//
//  ReaderLoader.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/17/26.
//

import Foundation
import Observation
import Readability
import ReadabilityUI

@MainActor
class ReaderLoader: ObservableObject {
    @Published var readerHTML: String?
    @Published var isLoading = false
    @Published var error: String?

    func load(from url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let readability = Readability()
            let result = try await readability.parse(url: url)
            let baseHTML: String = result.content

            let styledHTML = """
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    body {
                        font-family: -apple-system;
                        font-size: 18px;      /* slightly smaller than 20px */
                        line-height: 1.6;
                        /* less horizontal padding to reduce side whitespace */
                        padding: 8px 10px;
                        margin: 0;
                    }
                    p {
                        margin: 0 0 0.75em 0;
                    }
                    img {
                        max-width: 100%;
                        height: auto;
                        display: block;
                    }
                </style>
            </head>
            <body>
            \(baseHTML)
            </body>
            </html>
            """
            
            self.readerHTML = styledHTML
            
        } catch {
            self.error = "Could not load article."
            self.readerHTML = nil
        }
    }
}
