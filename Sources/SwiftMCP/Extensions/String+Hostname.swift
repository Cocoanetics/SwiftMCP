// String+Hostname.swift
// Hostname and IP-related extensions for String

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation


extension String {
/**
     Get the local hostname for EHLO/HELO commands
     - Returns: The local hostname
     */
    public static var localHostname: String {
        #if os(macOS) && !targetEnvironment(macCatalyst)
// Host is only available on macOS
        if let hostname = Host.current().name {
            return hostname
        }
        #else
// Use system call on Linux and other platforms
        var hostname = [CChar](repeating: 0, count: 256) // Linux typically uses 256 as max hostname length.
        if gethostname(&hostname, hostname.count) == 0 {
// Create a string from the C string
            if let name = String(cString: hostname, encoding: .utf8), !name.isEmpty {
                return name
            }
        }
        #endif

        return "localhost"
    }
}
