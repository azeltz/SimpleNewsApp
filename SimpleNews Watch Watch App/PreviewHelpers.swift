//
//  PreviewHelpers.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/4/26.
//

#if DEBUG
import SwiftUI

struct PreviewWrapper<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
    }
}
#endif
