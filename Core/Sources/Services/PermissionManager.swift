//
//  PermissionManager.swift
//  rBUM
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
import Foundation

/// A service that manages permission persistence and recovery for sandbox-compliant file access.
///
/// The `PermissionManager` provides a robust system for:
/// - Persisting security-scoped bookmarks
/// - Recovering file access permissions
/// - Sharing permissions with XPC services
/// - Managing permission lifecycle
///
/// ## Overview
///
/// Use `PermissionManager` to maintain persistent access to files and directories
/// selected by the user, even after app restart:
///
/// ```swift
/// let manager = PermissionManager(
///     logger: logger,
///     securityService: SecurityService(),
///     keychain: KeychainService()
/// )
///
/// // Store permission
/// try await manager.persistPermission(for: fileURL)
///
/// // Recover permission later
/// let hasAccess = try await manager.recoverPermission(for: fileURL)
/// ```
///
/// ## Topics
///
/// ### Permission Management
/// - ``persistPermission(for:)``
/// - ``recoverPermission(for:)``
/// - ``revokePermission(for:)``
///
/// ### Error Handling
/// - ``PermissionError``
public class PermissionManager {
    private let logger: LoggerProtocol
    private let securityService: SecurityServiceProtocol
    private let keychain: KeychainServiceProtocol
    private let fileManager: FileManager

    /// Prefix used for keychain permission entries to avoid naming conflicts
    private let keychainPrefix = "dev.mpy.rBUM.permission."

    /// Access group identifier for sharing permissions with the XPC service
    private let permissionAccessGroup = "dev.mpy.rBUM.permissions"

    /// Creates a new permission manager instance.
    ///
    /// - Parameters:
    ///   - logger: The logging service for debugging and diagnostics
    ///   - securityService: The service handling security-scoped bookmarks
    ///   - keychain: The service for securely storing permission data
    public init(
        logger: LoggerProtocol,
        securityService: SecurityServiceProtocol,
        keychain: KeychainServiceProtocol
    ) {
        self.logger = logger
        self.securityService = securityService
        self.keychain = keychain
        self.fileManager = FileManager.default

        do {
            try keychain.configureXPCSharing(accessGroup: permissionAccessGroup)
        } catch {
            self.logger.error(
                "Failed to configure XPC sharing: \(error.localizedDescription)",
                file: #file,
                function: #function,
                line: #line
            )
        }
    }

    /// Request and persist permission for a URL
    /// - Parameter url: The URL to request permission for
    /// - Returns: true if permission was granted and persisted
    public func requestAndPersistPermission(for url: URL) async throws -> Bool {
        logger.debug(
            "Requesting permission for: \(url.path)",
            file: #file,
            function: #function,
            line: #line
        )

        do {
            // Request permission
            guard try await securityService.requestPermission(for: url) else {
                logger.error(
                    "Permission denied for: \(url.path)",
                    file: #file,
                    function: #function,
                    line: #line
                )
                return false
            }

            // Create and store bookmark
            let bookmark = try await securityService.createBookmark(for: url)
            try persistBookmark(bookmark, for: url)

            logger.info(
                "Permission granted and persisted for: \(url.path)",
                file: #file,
                function: #function,
                line: #line
            )
            return true

        } catch {
            logger.error(
                "Failed to request/persist permission: \(error.localizedDescription)",
                file: #file,
                function: #function,
                line: #line
            )
            throw PermissionError.persistenceFailed(error.localizedDescription)
        }
    }

    /// Recover permission for a URL
    /// - Parameter url: The URL to recover permission for
    /// - Returns: true if permission was recovered
    public func recoverPermission(for url: URL) async throws -> Bool {
        logger.debug(
            "Attempting to recover permission for: \(url.path)",
            file: #file,
            function: #function,
            line: #line
        )

        do {
            // Check for existing bookmark
            guard let bookmark = try loadBookmark(for: url) else {
                logger.debug(
                    "No stored bookmark found for: \(url.path)",
                    file: #file,
                    function: #function,
                    line: #line
                )
                return false
            }

            // Attempt to resolve bookmark
            let resolvedURL = try securityService.resolveBookmark(bookmark)

            // Verify resolved URL matches original
            guard resolvedURL.path == url.path else {
                logger.error(
                    "Bookmark resolved to different path: \(resolvedURL.path)",
                    file: #file,
                    function: #function,
                    line: #line
                )
                try removeBookmark(for: url)
                return false
            }

            // Test access
            let canAccess = try await securityService.startAccessing(resolvedURL)
            guard canAccess else {
                logger.error(
                    "Failed to access resolved URL: \(resolvedURL.path)",
                    file: #file,
                    function: #function,
                    line: #line
                )
                try removeBookmark(for: url)
                return false
            }
            try await securityService.stopAccessing(resolvedURL)

            logger.info(
                "Successfully recovered permission for: \(url.path)",
                file: #file,
                function: #function,
                line: #line
            )
            return true

        } catch {
            logger.error(
                "Failed to recover permission: \(error.localizedDescription)",
                file: #file,
                function: #function,
                line: #line
            )

            // Clean up failed bookmark
            try? removeBookmark(for: url)

            throw PermissionError.recoveryFailed(error.localizedDescription)
        }
    }

    /// Check if permission exists for a URL
    /// - Parameter url: The URL to check
    /// - Returns: true if permission exists and is valid
    public func hasValidPermission(for url: URL) async throws -> Bool {
        do {
            guard let bookmark = try loadBookmark(for: url) else {
                return false
            }

            let resolvedURL = try securityService.resolveBookmark(bookmark)
            let canAccess = try await securityService.startAccessing(resolvedURL)
            if !canAccess {
                logger.error(
                    "Failed to access resolved URL: \(resolvedURL.path)",
                    file: #file,
                    function: #function,
                    line: #line
                )
                try removeBookmark(for: url)
                return false
            }
            return resolvedURL.path == url.path

        } catch {
            logger.debug(
                "Permission check failed: \(error.localizedDescription)",
                file: #file,
                function: #function,
                line: #line
            )
            return false
        }
    }

    /// Revoke permission for a URL
    /// - Parameter url: The URL to revoke permission for
    public func revokePermission(for url: URL) async throws {
        logger.debug(
            "Revoking permission for: \(url.path)",
            file: #file,
            function: #function,
            line: #line
        )

        do {
            try removeBookmark(for: url)
            logger.info(
                "Permission revoked for: \(url.path)",
                file: #file,
                function: #function,
                line: #line
            )

        } catch {
            logger.error(
                "Failed to revoke permission: \(error.localizedDescription)",
                file: #file,
                function: #function,
                line: #line
            )
            throw PermissionError.revocationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    private func persistBookmark(_ bookmark: Data, for url: URL) throws {
        logger.debug(
            "Persisting bookmark for: \(url.path)",
            file: #file,
            function: #function,
            line: #line
        )

        do {
            try keychain.save(bookmark, for: url.path, accessGroup: permissionAccessGroup)
        } catch {
            logger.error(
                "Failed to persist bookmark: \(error.localizedDescription)",
                file: #file,
                function: #function,
                line: #line
            )
            throw PermissionError.persistenceFailed(error.localizedDescription)
        }
    }

    private func loadBookmark(for url: URL) throws -> Data? {
        logger.debug(
            "Loading bookmark for: \(url.path)",
            file: #file,
            function: #function,
            line: #line
        )

        return try keychain.retrieve(for: url.path, accessGroup: permissionAccessGroup)
    }

    private func removeBookmark(for url: URL) throws {
        logger.debug(
            "Removing bookmark for: \(url.path)",
            file: #file,
            function: #function,
            line: #line
        )

        do {
            try keychain.delete(for: url.path, accessGroup: permissionAccessGroup)
        } catch {
            logger.error(
                "Failed to remove bookmark: \(error.localizedDescription)",
                file: #file,
                function: #function,
                line: #line
            )
            throw PermissionError.revocationFailed(error.localizedDescription)
        }
    }

    private func validateFileAccess(for url: URL) async throws {
        try await validateFileExists(at: url)
        try await validateFilePermissions(for: url)
        try await validateSandboxAccess(to: url)
    }

    private func validateFileExists(at url: URL) async throws {
        guard fileManager.fileExists(atPath: url.path) else {
            logger.error("File does not exist", metadata: [
                "path": .string(url.path)
            ])
            throw PermissionError.fileNotFound(url)
        }
    }

    private func validateFilePermissions(for url: URL) async throws {
        let resourceValues = try url.resourceValues(forKeys: [
            .isReadableKey,
            .isWritableKey,
            .fileProtectionKey
        ])

        guard resourceValues.isReadable else {
            logger.error("File is not readable", metadata: [
                "path": .string(url.path)
            ])
            throw PermissionError.readAccessDenied(url)
        }

        guard resourceValues.isWritable else {
            logger.error("File is not writable", metadata: [
                "path": .string(url.path)
            ])
            throw PermissionError.writeAccessDenied(url)
        }

        if let protection = resourceValues.fileProtection,
           protection == .complete {
            logger.error("File is encrypted", metadata: [
                "path": .string(url.path)
            ])
            throw PermissionError.fileEncrypted(url)
        }
    }

    private func validateSandboxAccess(to url: URL) async throws {
        let securityScopedURL = try await securityService.resolveBookmark(for: url)

        guard securityScopedURL.startAccessingSecurityScopedResource() else {
            logger.error("Failed to access security-scoped resource", metadata: [
                "path": .string(url.path)
            ])
            throw PermissionError.sandboxAccessDenied(url)
        }

        defer {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }

        try validateSandboxPermissions(for: securityScopedURL)
    }

    private func validateSandboxPermissions(for url: URL) throws {
        let resourceValues = try url.resourceValues(forKeys: [
            .volumeIsReadOnlyKey,
            .volumeSupportsFileCloningKey
        ])

        if let isReadOnly = resourceValues.volumeIsReadOnly,
           isReadOnly {
            logger.error("Volume is read-only", metadata: [
                "path": .string(url.path)
            ])
            throw PermissionError.volumeReadOnly(url)
        }

        if let supportsCloning = resourceValues.volumeSupportsFileCloning,
           !supportsCloning {
            logger.warning("Volume does not support file cloning", metadata: [
                "path": .string(url.path)
            ])
        }
    }
}

/// Errors that can occur during permission operations
public enum PermissionError: LocalizedError {
    case persistenceFailed(String)
    case recoveryFailed(String)
    case revocationFailed(String)
    case fileNotFound(URL)
    case readAccessDenied(URL)
    case writeAccessDenied(URL)
    case fileEncrypted(URL)
    case sandboxAccessDenied(URL)
    case volumeReadOnly(URL)

    public var errorDescription: String? {
        switch self {
        case let .persistenceFailed(reason):
            "Failed to persist permission: \(reason)"
        case let .recoveryFailed(reason):
            "Failed to recover permission: \(reason)"
        case let .revocationFailed(reason):
            "Failed to revoke permission: \(reason)"
        case let .fileNotFound(url):
            "File not found: \(url.path)"
        case let .readAccessDenied(url):
            "Read access denied for file: \(url.path)"
        case let .writeAccessDenied(url):
            "Write access denied for file: \(url.path)"
        case let .fileEncrypted(url):
            "File is encrypted: \(url.path)"
        case let .sandboxAccessDenied(url):
            "Sandbox access denied for file: \(url.path)"
        case let .volumeReadOnly(url):
            "Volume is read-only for file: \(url.path)"
        }
    }
}
