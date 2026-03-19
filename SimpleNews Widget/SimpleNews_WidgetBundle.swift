//
//  SimpleNews_WidgetBundle.swift
//  SimpleNews Widget
//
//  Created by Amir Zeltzer on 3/18/26.
//

import WidgetKit
import SwiftUI

@main
struct SimpleNews_WidgetBundle: WidgetBundle {
    var body: some Widget {
        SimpleNews_Widget()
        #if os(watchOS)
        SimpleNewsComplication()
        #endif
    }
}
