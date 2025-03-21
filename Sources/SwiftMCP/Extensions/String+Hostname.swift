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
			// Find the index of the null terminator.
			if let terminatorIndex = hostname.firstIndex(of: 0) {
				let hostnameSlice = hostname[..<terminatorIndex]
				// Convert the CChar slice to an array of UInt8.
				let uint8Hostname = hostnameSlice.map { UInt8(bitPattern: $0) }
				// Use the new initializer to validate the UTF8 string.
				if let name = String(validating: uint8Hostname, as: UTF8.self), !name.isEmpty {
					return name
				}
			}
		}
        #endif
        
        return "localhost"
    }
}
