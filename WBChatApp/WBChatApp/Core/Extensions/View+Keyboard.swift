//
//  View+Keyboard.swift
//  WBChatApp
//

import SwiftUI

extension View {

    /// 收起键盘（让当前第一响应者失焦）
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
