//
//  UnmatchedTitleNotice.swift
//  Manga-Reader
//
//  The per-title half of ADR-0015's absent-rail problem, and ADR-0005's first implied
//  requirement — *failures must become visible*.
//
//  `ForYouUnavailableNotice` only fires when the **whole** library is untaggable. Three
//  untaggable Works beside twenty taggable ones opens the gate, builds a rail, and leaves
//  those three omitted exactly as silently as before. This is what that reader sees on the
//  title itself.
//
//  It takes the "More Like This" slot for the same reason the other notice takes the "For
//  You" slot: that section is empty for this title, from this same cause, and an empty
//  section is the question the placement is answering.
//
//  Statement only, no action — unlike the rail notice, which can honestly say "read
//  something from MangaDex". Telling someone to go read a *different* title because they
//  opened this one is bad advice, and the real remedy (a manual link, ADR-0005) does not
//  exist yet.
//

import SwiftUI

struct UnmatchedTitleNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InkSectionHeader("More Like This", eyebrow: "Nothing to compare")

            VStack(alignment: .leading, spacing: 6) {
                Text("We couldn't match this title to a catalog.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.primary)
                Text("There's nothing to compare it against, so we can't suggest similar "
                     + "titles — and reading it isn't shaping your For You recommendations "
                     + "either.")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            // `surfaceAlt` + hairline, matching `ForYouUnavailableNotice` — and for the
            // reason ADR-0015's amendment 6 had to learn on a device: the seal wash is what
            // `InkNotice` fills an *error* with, and dropping the exclamation icon is not
            // enough on its own. The app is working correctly and has nothing to say about
            // this title.
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Ink.surfaceAlt)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.hairline, lineWidth: 1))
            )
            // The header sits flush like every other section's; only the card is inset —
            // the same arrangement `ForYouUnavailableNotice` uses in the For You slot.
            .padding(.horizontal, Gutter.page)
        }
        .accessibilityIdentifier("unmatchedTitleNotice")
    }
}
