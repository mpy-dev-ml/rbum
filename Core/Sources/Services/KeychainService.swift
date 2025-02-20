//
//  KeychainService.swift
//  rBUM
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
import Foundation
import Security

/// Service for managing secure storage in the Keychain
public final class KeychainService: BaseSandboxedService, Measurable {
    // MARK: - Properties

    let queue: DispatchQueue
    public private(set) var isHealthy: Bool

    // MARK: - Initialization

    override public init(logger: LoggerProtocol, securityService: SecurityServiceProtocol) {
        queue = DispatchQueue(label: "dev.mpy.rBUM.keychain", qos: .userInitiated)
        isHealthy = true // Default to true, will be updated by health checks
        super.init(logger: logger, securityService: securityService)
    }
}

// MARK: - Keychain Errors

/// Errors that can occur during keychain operations
public enum KeychainError: LocalizedError {
    case saveFailed(status: OSStatus)
    case updateFailed(status: OSStatus)
    case retrievalFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case invalidData
    case accessDenied

    public var errorDescription: String? {
        switch self {
        case let .saveFailed(status):
            "Failed to save to keychain: \(status)"
        case let .updateFailed(status):
            "Failed to update keychain item: \(status)"
        case let .retrievalFailed(status):
            "Failed to retrieve from keychain: \(status)"
        case let .deleteFailed(status):
            "Failed to delete from keychain: \(status)"
        case .invalidData:
            "Invalid data format"
        case .accessDenied:
            "Access denied to keychain"
        }
    }
}
