// String+Hostname.swift
// Hostname and IP-related extensions for String

import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

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
        var hostname = [CChar](repeating: 0, count: Int(256)) // Linux typically uses 256 as max hostname length
        if gethostname(&hostname, hostname.count) == 0 {
            if let name = String(validatingUTF8: hostname), !name.isEmpty {
                return name
            }
        }
        #endif
        
        return "localhost"
    }
}
