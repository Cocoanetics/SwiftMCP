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
    
    /**
     Get the local IP address
     - Returns: The local IP address as a string, or nil if not available
     */
    public static var localIPAddress: String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        
        defer {
            freeifaddrs(ifaddr)
        }
        
        // Iterate through linked list of interfaces
        var currentAddr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        var foundAddress: String? = nil
        
        while let addr = currentAddr {
            let interface = addr.pointee
            
            // Check for IPv4 or IPv6 interface
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                // Check interface name starts with "en" (Ethernet) or "wl" (WiFi)
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("wl") || name.hasPrefix("eth") {
                    // Convert interface address to a human readable string
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    
                    #if canImport(Darwin)
                    let saLen = socklen_t(interface.ifa_addr.pointee.sa_len)
                    #else
                    let saLen = addrFamily == UInt8(AF_INET) ? 
                        socklen_t(MemoryLayout<sockaddr_in>.size) : 
                        socklen_t(MemoryLayout<sockaddr_in6>.size)
                    #endif
                    
                    // Get address info
                    if getnameinfo(interface.ifa_addr, 
                                 saLen,
                                 &hostname, socklen_t(hostname.count),
                                 nil, 0,
                                 NI_NUMERICHOST) == 0 {
                        if let address = String(validatingUTF8: hostname) {
                            foundAddress = address
                            break
                        }
                    }
                }
            }
            
            // Move to next interface
            currentAddr = interface.ifa_next
        }
        
        return foundAddress
    }
} 
