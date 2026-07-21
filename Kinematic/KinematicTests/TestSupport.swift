//
//  TestSupport.swift
//  KinematicTests
//
//  Shared fixtures / helpers for the unit-test suite.
//

import Foundation
import XCTest
@testable import Kinematic

enum TestFixtures {
    /// Decode a `Lead` from a JSON body. Every field except `id` is optional
    /// on the model, so `{ "id": ... }` is the minimum valid row.
    static func lead(json body: String) throws -> Lead {
        try JSONDecoder().decode(Lead.self, from: Data(body.utf8))
    }

    /// A minimal `Lead` with just an id — handy for list/count assertions.
    static func lead(id: String) throws -> Lead {
        try lead(json: #"{"id":"\#(id)"}"#)
    }
}
