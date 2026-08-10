//
//  ForYouBasisNotice.swift
//  Manga-Reader
//
//  One line under the "For You" rail saying how much of the reader's history it is
//  actually based on — `RecommendationEngine.RailState.ready(tagged:of:)`.
//
//  ADR-0015 recorded the gap this fills as Hazard 3: three taggable Works alongside
//  twenty untaggable ones clears the gate and renders a rail built from an eighth of
//  the reader's taste. The rail is present, so the failure is not silent — merely
//  thin, and invisible. This is the number that makes it visible.
//
//  It is also how ADR-0017's novel filter gets verified in the app rather than in a
//  throwaway harness: the measurement that accepted it covered twelve hand-picked,
//  webtoon-skewed titles, and this reports the same ratio against the real library.
//
//  **Hidden when tagged == of.** A notice that renders unconditionally becomes
//  wallpaper within a day and stops being read; its absence is the healthy signal.
//  The accepted consequence is that if ADR-0017 worked as measured, this may never
//  appear — which is the outcome, not a failure to observe one.
//

import SwiftUI

struct ForYouBasisNotice: View {
    let tagged: Int
    let of: Int

    var body: some View {
        // "titles you've read", not Works or signals: `tagged`/`tags` is recommender
        // vocabulary that appears nowhere else in the UI. A basis, not a failure —
        // "3 titles couldn't be tagged" states the same fact as a defect report.
        Text("Based on \(tagged) of \(of) titles you've read")
            .font(.footnote)
            .foregroundStyle(Ink.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Gutter.page)
            .accessibilityIdentifier("forYouBasisNotice")
    }
}
