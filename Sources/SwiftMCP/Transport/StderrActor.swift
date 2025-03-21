#if canImport(Glibc)
@preconcurrency import Glibc
#endif

import Foundation

/// Actor to handle stderr access safely.
actor StderrActor {
    static let shared = StderrActor()
    
    /// Prints the given text to stderr.
    func print(_ text: String) {
        fputs("\(text)\n", stderr)
    }
} 