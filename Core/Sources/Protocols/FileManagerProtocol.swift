//
//  FileManagerProtocol.swift
//  rBUM
//
//  First created: 6 February 2025
//  Last updated: 6 February 2025
//
import Foundation

/// Protocol for file system operations, allowing for easier testing and sandbox compliance.
///
/// The `FileManagerProtocol` provides a safe interface for file operations while respecting
/// sandbox restrictions. Implementations must:
/// - Handle sandbox access restrictions appropriately
/// - Use security-scoped bookmarks when needed
/// - Clean up resources properly
/// - Handle permission errors gracefully
/// - Support both synchronous and asynchronous operations
///
/// Example usage:
/// ```swift
/// class BackupManager {
///     private let fileManager: FileManagerProtocol
///
///     init(fileManager: FileManagerProtocol) {
///         self.fileManager = fileManager
///     }
///
///     func backupFile(at url: URL) throws {
///         guard fileManager.fileExists(atPath: url.path) else {
///             throw BackupError.fileNotFound
///         }
///         // Perform backup operations...
///     }
/// }
/// ```
///
/// - Note: All operations must be performed within the app's sandbox boundaries
/// - Important: Always check for file existence before performing operations
public protocol FileManagerProtocol {
    /// Check if a file exists and is accessible at the given path
    /// - Parameter path: The path to check
    /// - Returns: True if the file exists and is accessible
    /// - Note: This operation respects sandbox restrictions
    func fileExists(atPath path: String) -> Bool

    /// Check if a file exists and get its type
    /// - Parameters:
    ///   - path: The path to check
    ///   - isDirectory: Pointer to receive directory status
    /// - Returns: True if the file exists and is accessible
    /// - Note: The isDirectory parameter will be set to true for directories
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool

    /// Create a directory at the given URL
    /// - Parameters:
    ///   - url: The URL where the directory should be created
    ///   - createIntermediates: If true, creates intermediate directories
    ///   - attributes: Optional attributes for the new directory
    /// - Throws: FileError if creation fails due to permissions or sandbox restrictions
    /// - Note: Ensure you have proper sandbox entitlements for the target location
    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws

    /// Remove item at the given URL
    /// - Parameter url: The URL of the item to remove
    /// - Throws: FileError if removal fails due to permissions or sandbox restrictions
    /// - Important: This operation cannot be undone
    func removeItem(at url: URL) throws

    /// Get contents of a file at the given path
    /// - Parameter path: The path to read from
    /// - Returns: The file contents as Data, or nil if the file cannot be read
    /// - Note: Returns nil if sandbox restrictions prevent access
    func contents(atPath path: String) -> Data?

    /// Write data to a file at the given path
    /// - Parameters:
    ///   - path: The path to write to
    ///   - data: The data to write
    ///   - attr: Optional attributes for the new file
    /// - Returns: True if the write was successful
    /// - Note: Ensure proper sandbox entitlements for the target location
    func createFile(
        atPath path: String,
        contents data: Data?,
        attributes attr: [FileAttributeKey: Any]?
    ) -> Bool

    /// Copy an item from one location to another
    /// - Parameters:
    ///   - srcURL: The source URL
    ///   - dstURL: The destination URL
    /// - Throws: FileError if the copy fails due to permissions or sandbox restrictions
    /// - Note: Ensure proper sandbox entitlements for the target location
    func copyItem(at srcURL: URL, to dstURL: URL) throws

    /// Move an item from one location to another
    /// - Parameters:
    ///   - srcURL: The source URL
    ///   - dstURL: The destination URL
    /// - Throws: FileError if the move fails due to permissions or sandbox restrictions
    /// - Important: This operation cannot be undone
    func moveItem(at srcURL: URL, to dstURL: URL) throws

    /// Get attributes of an item
    /// - Parameter path: The path to get attributes for
    /// - Returns: The attributes dictionary, or nil if not accessible
    /// - Throws: FileError if access is denied due to sandbox restrictions
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]

    /// List contents of a directory
    /// - Parameter url: The directory URL to list
    /// - Returns: Array of URLs for the directory contents
    /// - Throws: FileError if the directory cannot be read due to sandbox restrictions
    /// - Note: Ensure proper sandbox entitlements for the target location
    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL]
}

/// Errors that can occur during file operations
public enum FileError: LocalizedError {
    case fileNotFound(path: String)
    case accessDenied(path: String)
    case alreadyExists(path: String)
    case invalidPath(path: String)
    case operationFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            "File not found at path: \(path)"
        case let .accessDenied(path):
            "Access denied to path: \(path)"
        case let .alreadyExists(path):
            "File already exists at path: \(path)"
        case let .invalidPath(path):
            "Invalid path: \(path)"
        case let .operationFailed(path, reason):
            "Operation failed for path: \(path), reason: \(reason)"
        }
    }
}

/// Default implementation of FileManagerProtocol using FileManager
public struct DefaultFileManager: FileManagerProtocol {
    private let fileManager = FileManager.default

    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    public func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        fileManager.fileExists(atPath: path, isDirectory: isDirectory)
    }

    public func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: createIntermediates,
                attributes: attributes
            )
        } catch CocoaError.fileWriteNoPermission {
            throw FileError.accessDenied(path: url.path)
        } catch CocoaError.fileWriteFileExists {
            throw FileError.alreadyExists(path: url.path)
        } catch {
            throw FileError.operationFailed(path: url.path, reason: error.localizedDescription)
        }
    }

    public func removeItem(at url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            throw FileError.fileNotFound(path: url.path)
        } catch CocoaError.fileWriteNoPermission {
            throw FileError.accessDenied(path: url.path)
        } catch {
            throw FileError.operationFailed(path: url.path, reason: error.localizedDescription)
        }
    }

    public func contents(atPath path: String) -> Data? {
        fileManager.contents(atPath: path)
    }

    public func createFile(
        atPath path: String,
        contents data: Data?,
        attributes attr: [FileAttributeKey: Any]?
    ) -> Bool {
        fileManager.createFile(
            atPath: path,
            contents: data,
            attributes: attr
        )
    }

    public func copyItem(at srcURL: URL, to dstURL: URL) throws {
        do {
            try fileManager.copyItem(at: srcURL, to: dstURL)
        } catch CocoaError.fileNoSuchFile {
            throw FileError.fileNotFound(path: srcURL.path)
        } catch CocoaError.fileWriteNoPermission {
            throw FileError.accessDenied(path: dstURL.path)
        } catch CocoaError.fileWriteFileExists {
            throw FileError.alreadyExists(path: dstURL.path)
        } catch {
            throw FileError.operationFailed(
                path: srcURL.path,
                reason: error.localizedDescription
            )
        }
    }

    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        do {
            try fileManager.moveItem(at: srcURL, to: dstURL)
        } catch CocoaError.fileNoSuchFile {
            throw FileError.fileNotFound(path: srcURL.path)
        } catch CocoaError.fileWriteNoPermission {
            throw FileError.accessDenied(path: dstURL.path)
        } catch CocoaError.fileWriteFileExists {
            throw FileError.alreadyExists(path: dstURL.path)
        } catch {
            throw FileError.operationFailed(
                path: srcURL.path,
                reason: error.localizedDescription
            )
        }
    }

    public func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        do {
            return try fileManager.attributesOfItem(atPath: path)
        } catch CocoaError.fileNoSuchFile {
            throw FileError.fileNotFound(path: path)
        } catch CocoaError.fileReadNoPermission {
            throw FileError.accessDenied(path: path)
        } catch {
            throw FileError.operationFailed(path: path, reason: error.localizedDescription)
        }
    }

    public func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: mask
            )
        } catch CocoaError.fileNoSuchFile {
            throw FileError.fileNotFound(path: url.path)
        } catch CocoaError.fileReadNoPermission {
            throw FileError.accessDenied(path: url.path)
        } catch {
            throw FileError.operationFailed(path: url.path, reason: error.localizedDescription)
        }
    }
}
