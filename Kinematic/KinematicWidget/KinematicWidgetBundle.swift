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
        KinematicWidget()          // CRM summary (leads/deals/pipeline)
        KinematicLeadWidget()      // Lead management
        KinematicFieldForceWidget() // Field-force / my day / team
        // KinematicWidgetControl itself is @available(iOS 18.0, *) (Control widgets are an
        // iOS-18-only API) — gate its inclusion here too, so a build whose effective target
        // for this file resolves below 18 (see that file's header) simply omits it.
        if #available(iOS 18.0, *) {
            KinematicWidgetControl() // Control Center: check-in status
        }
    }
}
