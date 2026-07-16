//
//  SourceContext.swift
//  Manga-Reader
//
//  The host-capability bundle handed to every `MangaSource` at construction. Sources
//  that scrape HTML sites call `webView.extract(...)`; API-backed sources (MangaDex)
//  ignore it. More capabilities (net, storage) join in later phases when a source
//  actually needs them.
//

import Foundation

/// Loads a page in a real browser (clearing Cloudflare as needed), runs a JS extraction
/// script whose final expression is a `JSON.stringify(...)` string, and decodes it.
/// Implemented by `WebViewService`; mocked in tests.
protocol WebViewExtracting {
    func extract<T: Decodable>(from url: URL, script: String, as type: T.Type) async throws -> T
}

/// Capabilities available to sources. Built once by `SourceRegistry` and shared.
struct SourceContext {
    let webView: WebViewExtracting
}
