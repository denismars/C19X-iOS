//
//  ControllerTest.swift
//  C19XTests
//
//  Created by Freddy Choi on 18/06/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import XCTest
@testable import C19X

class ControllerTest: XCTestCase {

    func testExample() throws {
        let controller = ConcreteController()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let date = dateFormatter.date(from: "2020-06-18T00:00:00")!
        let now = dateFormatter.date(from: "2020-06-19T05:59:00")!
        XCTAssert(controller.oncePerDay(date, now: now))
    }
}
