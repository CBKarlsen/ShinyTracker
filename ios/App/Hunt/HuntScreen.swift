import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// The Hunt tab. Layout, spacing and colour come from `docs/design/hunt-prototype.dc.html`.
///
/// Only the **Active** segment is built. History and Games are placeholders, as are the header's
/// search button (it opens the Reference sheet, which is not built) and the + button.
struct HuntScreen: View {
    @State var model: HuntListModel
    @State private var segment: Segment = .active

    /// `tabs: [{label:'Active'}, {label:'History'}, {label:'Games'}]`.
    enum Segment: String, CaseIterable, Identifiable {
        case active = "Active", history = "History", games = "Games"
        var id: Self { self }
    }

    var body: some View {
        // `gap:13px;padding:8px 18px 0`
        VStack(alignment: .leading, spacing: Metrics.screenGap) {
            header
            segmentedControl
            content
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await model.load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            // `gap:9px` — mode glyph then title. The prototype's glyph is a shiny-charm PNG we
            // do not have as an asset; `sparkles` is the nearest system symbol and is used for
            // the ✦ found button too, keeping one glyph for "shiny" throughout.
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.hunt.color)
                Text("Hunt")
                    .font(Typography.screenTitle)
                    .tracking(Typography.screenTitleTracking)
                    .foregroundStyle(Palette.textPrimary.color)
            }

            Spacer(minLength: 0)

            Text(huntSummary)
                .font(Typography.summary)
                .foregroundStyle(Palette.textMuted.color)

            // Reference search. Present per the design ("reachable from every header"), inert:
            // the Reference sheet is out of scope.
            headerButton(symbol: "magnifyingglass", label: "Search the reference") {}
                .foregroundStyle(Palette.textSecondary.color)
                .background(Palette.surface.color, in: .rect(cornerRadius: Radii.headerButton))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.headerButton)
                        .strokeBorder(Palette.hairline.color, lineWidth: 1)
                )

            // The gold +. The new-hunt flow is out of scope, so it is inert too.
            headerButton(symbol: "plus", label: "Start a new hunt") {}
                .fontWeight(.bold)
                .foregroundStyle(Palette.onAccent.color)
                .background(Palette.hunt.color, in: .rect(cornerRadius: Radii.headerButton))
        }
    }

    /// `${n} ${n === 1 ? 'hunt' : 'hunts'}`.
    private var huntSummary: String {
        let count = model.rows.count
        return "\(count) \(count == 1 ? "hunt" : "hunts")"
    }

    private func headerButton(
        symbol: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: Metrics.headerButton, height: Metrics.headerButton)
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
    }

    // MARK: Segmented control

    /// `display:flex;gap:2px;background:#111118;border:1px solid #1a1a22;border-radius:12px;padding:3px`
    private var segmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(Segment.allCases) { tab in
                let on = tab == segment
                Button { segment = tab } label: {
                    Text(tab.rawValue)
                        .font(on ? Typography.segmentOn : Typography.segmentOff)
                        .foregroundStyle((on ? Palette.onAccent : Palette.textMuted).color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            on ? Palette.textPrimary.color : .clear,
                            in: .rect(cornerRadius: Radii.segmentItem)
                        )
                        .contentShape(.rect)
                }
            }
        }
        .padding(3)
        .background(Palette.surface.color, in: .rect(cornerRadius: Radii.segment))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.segment)
                .strokeBorder(Palette.hairline.color, lineWidth: 1)
        )
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .active: activeList
        case .history: placeholder("History", "Finished hunts land here. Not built yet.")
        case .games: placeholder("Games", "Your library and the Shiny Charm. Not built yet.")
        }
    }

    @ViewBuilder
    private var activeList: some View {
        switch model.state {
        case .loading:
            centered {
                ProgressView().tint(Palette.textMuted.color)
            }

        case .failed(let reason):
            centered {
                stateBlock(
                    symbol: "exclamationmark.triangle",
                    title: "Couldn't load your hunts",
                    body: reason
                ) {
                    Button("Try again") { Task { await model.load() } }
                        .buttonStyle(GoldButtonStyle())
                        .padding(.top, 22)
                }
            }

        case .ready:
            // `overflow-y:auto;gap:10px;padding-bottom:104px`
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.cardGap) {
                    if let syncError = model.syncError {
                        Text(syncError)
                            .font(Typography.hint)
                            .foregroundStyle(Palette.nuzlocke.color)
                            .padding(.horizontal, 2)
                    }

                    if model.rows.isEmpty {
                        emptyState
                    } else {
                        // `countHint` — the prototype promises Space/volume-up counting, ⌘Z undo
                        // and a wake lock. None of those exist here (volume counting is ruled
                        // out by DECISIONS.md D3), so the line says only what is true.
                        Text("Tap +1 to count. ×N changes how many each tap adds.")
                            .font(Typography.hint)
                            .foregroundStyle(Palette.textMuted.color)
                            .padding(.horizontal, 2)
                            .padding(.top, 2)

                        ForEach(model.rows) { row in
                            HuntCard(row: row, model: model, isLive: row.id == model.liveHuntID)
                        }
                    }
                }
                .padding(.bottom, Metrics.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.load() }
        }
    }

    /// The owner has zero hunts, so this is the first thing they will see.
    private var emptyState: some View {
        stateBlock(
            symbol: "sparkles",
            title: "No active hunts",
            body: "Every shiny you've caught is in History. Start the next one whenever you're ready."
        )
        .padding(.top, 6)
    }

    private func placeholder(_ title: String, _ body: String) -> some View {
        centered { stateBlock(symbol: "square.dashed", title: title, body: body) }
    }

    /// `padding:52px 24px` panel with a 64pt icon tile — the prototype's empty state, reused for
    /// the error and placeholder states because it is the same shape.
    private func stateBlock(
        symbol: String,
        title: String,
        body: String,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(Palette.hunt.color.opacity(0.55))
                .frame(width: 64, height: 64)
                .background(Palette.surface.color, in: .rect(cornerRadius: Radii.iconTile))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.iconTile)
                        .strokeBorder(Palette.hairline.color, lineWidth: 1)
                )
                .padding(.bottom, 20)

            Text(title)
                .font(Typography.emptyTitle)
                .tracking(Typography.cardTitleTracking)
                .foregroundStyle(Palette.textPrimary.color)
                .padding(.bottom, 10)

            Text(body)
                .font(Typography.emptyBody)
                .lineSpacing(4)
                .foregroundStyle(Palette.textMuted.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)

            accessory()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .padding(.horizontal, 24)
        .background(Palette.surfaceSunken.color, in: .rect(cornerRadius: Radii.panel))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.panel)
                .strokeBorder(Palette.hairline.color, lineWidth: 1)
        )
    }

    private func centered(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            content().padding(.top, 6)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// `height:52px;border-radius:16px;background:#f5c661;color:#060608;font:600 18px/1`
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.primaryButton)
            .foregroundStyle(Palette.onAccent.color)
            .padding(.horizontal, 22)
            .frame(height: 46)
            .background(Palette.hunt.color, in: .rect(cornerRadius: Radii.headerButton))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
