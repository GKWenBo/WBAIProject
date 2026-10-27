//
//  SmokeTests.swift
//  TextKitExampleTests
//

import Testing
@testable import TextKitExample

@Suite("工程骨架")
struct SmokeTests {

    @Test("案例目录有 8 条且编号连续")
    func catalogIsComplete() {
        #expect(CaseCatalog.all.count == 8)
        #expect(CaseCatalog.all.map(\.number) == Array(1...8))
    }
}
