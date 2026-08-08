//
//  ForYouUnavailableNotice.swift
//  Manga-Reader
//
//  What the "For You" slot renders when the rail can never open on the reader's
//  current library — `RecommendationEngine.RailState.noTaggableSignal` (ADR-0015).
//
//  Deliberately NOT `InkNotice`: that carries an exclamation mark and reads as an
//  error, and this is not one. The app is working correctly and has nothing to
//  recommend. Only this one state gets words — cold start stays silent, because the
//  defect ADR-0015 fixes is that a permanent dead end was indistinguishable from it.
//

import SwiftUI

struct ForYouUnavailableNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InkSectionHeader("For You", eyebrow: "Nothing to go on yet")

            VStack(alignment: .leading, spacing: 6) {
                Text("For You needs titles we can identify.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.primary)
                // The last clause is the reason this notice exists. An empty rail implies
                // "keep reading", which is a lie in exactly this case; naming an action
                // that actually works is the whole payoff.
                //
                // "reading", not "adding" — saving a title contributes no entries, so it
                // never moves `taggedMangaCount` (ADR-0015 amendment 4).
                Text("The manga in your history come from sources we can't match to a "
                     + "catalog, so there's nothing to base recommendations on yet. "
                     + "Reading more from these sources won't change that — but reading a "
                     + "title from MangaDex will.")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Ink.sealSoft))
            .padding(.horizontal, Gutter.page)
        }
        .accessibilityIdentifier("forYouUnavailableNotice")
    }
}
