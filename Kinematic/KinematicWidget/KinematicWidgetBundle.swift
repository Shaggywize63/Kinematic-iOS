//
//  KinematicWidgetBundle.swift
//  KinematicWidget
//
//  Bundle entry point — exposes the KinematicWidget definition so iOS
//  can list it in the widget gallery and the user can pick small,
//  medium, or large.
//
//  ⚠️ This file lives in a separate KinematicWidget extension target.
//  In Xcode: File → New → Target → "Widget Extension", point its
//  Sources to this folder, and link it against `WidgetKit` + SwiftUI.
//  The host app target must also enable the same App Group so the
//  app + widget can share the cached summary.
//

import WidgetKit
import SwiftUI

@main
struct KinematicWidgetBundle: WidgetBundle {
    var body: some Widget {
        KinematicWidget()
    }
}
