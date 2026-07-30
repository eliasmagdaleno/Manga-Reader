//
//  ReaderBanner.swift
//  Manga-Reader
//
//  ADR-0012 / ADR-0013. A failure surfaced *over* readable content, as opposed to
//  instead of it — the shape a failed chapter advance takes once load-then-commit
//  keeps the chapter you were reading on screen.
//
//  `InkNotice` could not be reused: it is a block element that fills its container's
//  width and sits in the layout flow (`HomeView.swift:176-192`). This floats over a
//  full-bleed pager, so it carries the reader chrome's own surface treatment instead.
//
//  It is a `Button` on purpose, for the same reason `PageRetry` is: a plain tap gesture
//  here would fight the reader's chrome-toggle tap, and a `Button`'s tap wins.
//

import SwiftUI

struct ReaderBanner: View {
    let message: String
    let onDismiss: () -> Void

    init(_ message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
    }

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.seal)

                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Not a second control — the whole banner is the button. This just says so.
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Ink.surface.opacity(0.96)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Gutter.page)
    }
}
