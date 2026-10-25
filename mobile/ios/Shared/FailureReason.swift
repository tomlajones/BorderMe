import Foundation

enum FailureReason {
    /// A short reason shown beside a skipped photo.
    static func describe(_ error: Error) -> String {
        if let engineError = error as? BorderEngineError { return engineError.reason }
        if error is LibraryWriterError { return "could not be saved to Photos" }
        return "could not be processed"
    }
}
