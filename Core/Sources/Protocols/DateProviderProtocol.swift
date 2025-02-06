//
//  DateProviderProtocol.swift
//  rBUM
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
//  Created by Matthew Yeager on 03/02/2025.
//

import Foundation

/// Protocol for providing dates, allowing for easier testing of time-dependent code
public protocol DateProviderProtocol {
    /// Get the current date and time
    func now() -> Date
}

/// Default implementation of DateProviderProtocol using system time
public struct DateProvider: DateProviderProtocol {
    public init() {}
    
    public func now() -> Date {
        return Date()
    }
}
