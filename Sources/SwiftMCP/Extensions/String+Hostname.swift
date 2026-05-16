// String+Hostname.swift
// Hostname and IP-related extensions for String

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
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
        #elseif os(Windows)
        // `gethostname()` on Windows is a Winsock function and requires
        // `WSAStartup()` to have been called first; without that it
        // returns `WSANOTINITIALISED` and we'd silently fall back to
        // `"localhost"`. `GetComputerNameExW(_:_:_:)` reads the
        // configured DNS hostname directly from the local registry
        // without touching Winsock — the right tool for EHLO/HELO.
        var size: DWORD = 256
        var buffer = [WCHAR](repeating: 0, count: Int(size))
        if GetComputerNameExW(ComputerNameDnsFullyQualified, &buffer, &size) {
            let name = String(decodingCString: buffer, as: UTF16.self)
            if !name.isEmpty {
                return name
            }
        }
        #else
        // POSIX: Linux / Android / musl all expose `gethostname(_:_:)`
        // through their respective libc shim imported above.
        var hostname = [CChar](repeating: 0, count: 256) // POSIX HOST_NAME_MAX is 64; 256 is generous.
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
