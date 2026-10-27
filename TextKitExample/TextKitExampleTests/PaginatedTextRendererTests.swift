//
//  PaginatedTextRendererTests.swift
//  TextKitExampleTests
//

import Testing
import UIKit
@testable import TextKitExample

@MainActor
@Suite("分页")
struct PaginatedTextRendererTests {

    private static let pageSize = CGSize(width: 280, height: 200)

    @Test("长文会分成多页")
    func splitsIntoPages() {
        let renderer = PaginatedTextRenderer(text: SampleText.articleAttributed())
        let pageCount = renderer.paginate(pageSize: Self.pageSize)

        #expect(pageCount > 1)
        #expect(renderer.containers.count == pageCount)
    }

    @Test("各页字符范围首尾相接、无重叠、并集等于全文")
    func rangesCoverWholeText() {
        let text = SampleText.articleAttributed()
        let renderer = PaginatedTextRenderer(text: text)
        let pageCount = renderer.paginate(pageSize: Self.pageSize)

        var expectedLocation = 0
        for page in 0..<pageCount {
            let range = renderer.characterRange(forPage: page)
            #expect(range.location == expectedLocation, "第 \(page + 1) 页起点不接上一页")
            expectedLocation = NSMaxRange(range)
        }
        #expect(expectedLocation == text.length)
    }

    @Test("页面变大时页数变少")
    func repaginateOnSizeChange() {
        let renderer = PaginatedTextRenderer(text: SampleText.articleAttributed())
        let small = renderer.paginate(pageSize: Self.pageSize)
        let large = renderer.paginate(pageSize: CGSize(width: 320, height: 600))

        #expect(large < small)
        #expect(renderer.containers.count == large)
    }

    @Test("空文本分出 0 页")
    func emptyText() {
        let renderer = PaginatedTextRenderer(text: NSAttributedString())
        #expect(renderer.paginate(pageSize: Self.pageSize) == 0)
        #expect(renderer.containers.isEmpty)
    }

    @Test("越界页号返回空范围")
    func outOfRangePage() {
        let renderer = PaginatedTextRenderer(text: SampleText.articleAttributed())
        renderer.paginate(pageSize: Self.pageSize)

        #expect(renderer.characterRange(forPage: 9_999).length == 0)
    }
}
