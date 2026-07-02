//
//  Item.swift
//  WBChatApp
//
//  Created by 文波 on 2026/7/2.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
