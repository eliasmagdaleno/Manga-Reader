//
//  SafariView.swift
//  MangaCarta
//
//  In-app Safari (SFSafariViewController) presented as a sheet — used by the manga
//  detail screen's "open on web" action so users never leave the app.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
