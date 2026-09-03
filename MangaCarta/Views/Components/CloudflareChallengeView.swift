//
//  CloudflareChallengeView.swift
//  MangaCarta
//
//  Sheet content that puts WebViewService's shared browser on screen while a
//  Cloudflare interactive challenge needs a human tap. Purely presentational:
//  the service decides when a challenge is active and when it's cleared.
//

import SwiftUI
import WebKit

struct CloudflareChallengeView: View {
    @ObservedObject private var service = WebViewService.shared

    var body: some View {
        NavigationStack {
            ChallengeWebViewHost(webView: service.webView)
                .navigationTitle("Verification Required")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            service.cancelChallenge()
                        }
                    }
                }
        }
    }
}

/// Hosts the service's existing WKWebView instance (never creates its own —
/// the challenge must run in the same browser that holds the cookies).
private struct ChallengeWebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
