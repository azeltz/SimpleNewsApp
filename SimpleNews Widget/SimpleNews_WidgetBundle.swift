//
//  SimpleNews_WidgetBundle.swift
//  SimpleNews Widget
//
//  Created by Amir Zeltzer on 3/4/26.
//

import WidgetKit
import SwiftUI

@main
struct SimpleNews_WidgetBundle: WidgetBundle {
    var body: some Widget {
        SimpleNews_Widget()
        SimpleNews_WidgetControl()
        SimpleNews_WidgetLiveActivity()
    }
}
