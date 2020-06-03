//
//  Utilities.swift
//  C19X
//
//  Created by Freddy Choi on 26/05/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation

extension Date {
    
    var description: String { get {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
        return dateFormatter.string(from: self)
        } }
    
    func elapsed() -> String {
        let elapsedSeconds = distance(to: Date()).magnitude
        if (elapsedSeconds < 60) {
            return "just now"
        } else if (elapsedSeconds < 3600) {
            let elapsedMinutes = Int((elapsedSeconds / 60).rounded())
            return String(elapsedMinutes) + "m ago"
        } else if (elapsedSeconds < 24 * 3600) {
            let elapsedHours = Int((elapsedSeconds / 3600).rounded())
            return String(elapsedHours) + "h ago"
        } else {
            let elapsedDays = Int((elapsedSeconds / (24 * 3600)).rounded())
            return String(elapsedDays) + "d ago"
        }
    }
}
