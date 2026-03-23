//
//  HTTPHandler+URLSessionTaskDelegate.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 23.03.26.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPHandler: URLSessionTaskDelegate
{
    // MARK: - URLSessionTaskDelegate
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Don't follow redirects. Let the original data task complete with the redirect response.
        logger.info("URLSession delegate detected redirect, preventing follow.")
        completionHandler(nil)
    }
}
