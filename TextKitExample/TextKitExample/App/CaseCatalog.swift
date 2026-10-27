//
//  CaseCatalog.swift
//  TextKitExample
//

import UIKit

/// 一个案例的元数据。
struct CaseEntry {
    let number: Int
    let title: String
    let subtitle: String
    /// 用的是哪套 TextKit，以及为什么。
    let badge: String
    let make: () -> UIViewController
}

/// 案例目录。首页列表和导航都由它驱动，新增案例只改这一处。
enum CaseCatalog {

    static let all: [CaseEntry] = [
        CaseEntry(number: 1,
                  title: "文本高度预计算 / 后台排版",
                  subtitle: "列表测高走独立 TextKit 栈，结果可缓存",
                  badge: "TextKit 2",
                  make: { HeightCacheViewController() }),
        CaseEntry(number: 2,
                  title: "UILabel 字符级点击",
                  subtitle: "链接 / @ / 话题，坐标换算成字符索引",
                  badge: "TextKit 1",
                  make: { LabelHitTestViewController() }),
        CaseEntry(number: 3,
                  title: "自定义背景装饰",
                  subtitle: "代码块底色、引用竖线、行内圆角高亮",
                  badge: "TextKit 1",
                  make: { DecorationViewController() }),
        CaseEntry(number: 4,
                  title: "文字环绕（图文混排）",
                  subtitle: "exclusionPaths 让文字自动绕开区域",
                  badge: "TextKit 1",
                  make: { TextWrapViewController() }),
        CaseEntry(number: 5,
                  title: "分页 / 多栏",
                  subtitle: "一个 layoutManager 挂多个容器，文字自动流",
                  badge: "TextKit 1",
                  make: { PaginationViewController() }),
        CaseEntry(number: 6,
                  title: "语法高亮编辑器",
                  subtitle: "NSTextStorage 子类，只重算编辑过的行",
                  badge: "TextKit 1",
                  make: { SyntaxHighlightViewController() }),
        CaseEntry(number: 7,
                  title: "截断与「…展开」",
                  subtitle: "精确判断第 N 行在哪截断，再拼展开按钮",
                  badge: "TextKit 1",
                  make: { TruncationViewController() }),
        CaseEntry(number: 8,
                  title: "行信息与选区",
                  subtitle: "enumerateLineFragments 拿每行的 rect 与范围",
                  badge: "TextKit 1",
                  make: { LineMetricsViewController() })
    ]
}
