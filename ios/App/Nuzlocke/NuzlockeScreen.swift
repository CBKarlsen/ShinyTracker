import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// The Nuzlocke mode — screens `1h` and `2b` of `docs/design/mobile-app.dc.html`.
///
/// "Blue = Nuzlocke … so a run screen never shows gold." One open run: the checkpoint you are
/// walking towards, who is alive, and the route timeline you log against.
struct NuzlockeScreen: View {
    @State var model: NuzlockeModel
    @State private var startingRun = false
    @State private var pickingRun = false
    @State private var loggingAt: NuzlockeTimelineEntry?
    @State private var openBoss: NuzlockeTimelineEntry?
    @State private var showingRoster = false

    /// The run's game is the title, the level cap its subtitle, and switching runs is a toolbar
    /// button — so the large title collapses on scroll and the timeline gets the space back.
    ///
    /// The cap moved from a coloured badge to the subtitle deliberately: it is the rule you check
    /// constantly, so it belongs somewhere always visible rather than in a decoration that
    /// scrolls.
    var body: some View {
        NavigationStack {
            content
                // The root is a NavigationStack now; insetting it would inset the bar too.
                .padding(.horizontal, Metrics.screenPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle(model.run?.gameTitle ?? "Nuzlocke")
                .navigationSubtitle(capLabel)
                .toolbar {
                    if !model.runs.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { pickingRun = true } label: {
                                Image(systemName: "square.stack.3d.up")
                            }
                            .accessibilityLabel("Switch run")
                        }
                    }
                }
        }
        .task { await model.appear() }
        // A second `.task` so the species table — one big request, and only the coverage warning
        // needs it — loads alongside the run rather than delaying it.
        .task { await model.loadSpeciesTypes() }
        .sheet(isPresented: $startingRun) {
            NewRunSheet(model: model)
        }
        .sheet(isPresented: $pickingRun) {
            RunPickerSheet(model: model)
        }
        .sheet(item: $loggingAt) { entry in
            EncounterSheet(model: model, location: entry)
        }
        .sheet(item: $openBoss) { boss in
            CheckpointSheet(model: model, boss: boss)
        }
        .sheet(isPresented: $showingRoster) {
            RosterSheet(model: model)
        }
    }

    // MARK: Title

    /// "Level cap 33" — the one number that governs a run. Empty before a run loads; an empty
    /// subtitle renders as no subtitle, which is what should happen when there is no cap.
    private var capLabel: String {
        guard let cap = model.levelCap else { return "" }
        return "Level cap \(cap)"
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .tint(Palette.textMuted.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let reason):
            StateBlock(
                symbol: "exclamationmark.triangle",
                title: "Couldn't load your runs",
                body: reason,
                tint: Palette.nuzlocke
            ) {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(BlueButtonStyle())
                    .padding(.top, 22)
            }

        case .ready:
            if model.run == nil {
                emptyState
            } else {
                runBody
            }
        }
    }

    private var emptyState: some View {
        StateBlock(
            symbol: "list.bullet.rectangle",
            title: "No run yet",
            body: "A run walks one game's routes in order. One encounter each, faint is death.",
            tint: Palette.nuzlocke
        ) {
            Button("Start a run") { startingRun = true }
                .buttonStyle(BlueButtonStyle())
                .padding(.top, 22)
        }
    }

    private var runBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.cardGap) {
                Text(model.runSummary)
                    .font(Typography.summary)
                    .foregroundStyle(Palette.textMuted.color)

                if let message = model.syncError {
                    Text(message)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                checkpointCard
                coverageCard
                partyStrip

                Text("Encounters")
                    .font(Typography.blockLabel)
                    .tracking(Typography.blockLabelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textMuted.color)
                    .padding(.top, 6)

                ForEach(model.timeline) { entry in
                    if entry.isBoss {
                        checkpointRow(entry)
                    } else {
                        locationRow(entry)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
        .overlay {
            if model.loadingRun {
                ProgressView().tint(Palette.textMuted.color)
            }
        }
    }

    // MARK: Checkpoint

    /// "Next checkpoint — Veilstone City · Gym 4 — Maylene". The run's whole direction in one
    /// card, and the source of the level cap in the header.
    @ViewBuilder
    private var checkpointCard: some View {
        if let boss = model.nextCheckpoint {
            Button { openBoss = boss } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Next checkpoint")
                        .font(Typography.blockLabel)
                        .tracking(Typography.blockLabelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.nuzlocke.color)
                    Text(boss.place ?? boss.name)
                        .font(Typography.cardTitle)
                        .tracking(Typography.cardTitleTracking)
                        .foregroundStyle(Palette.textPrimary.color)
                    Text([boss.bossTitle, boss.name].compactMap { $0 }.joined(separator: " — "))
                        .font(Typography.meta)
                        .foregroundStyle(Palette.textSecondary.color)
                    if let squad = boss.squad, !squad.isEmpty {
                        Text(
                            "\(squad.count) Pokémon · up to Lv \(squad.map(\.level).max() ?? 0)"
                        )
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textMuted.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.cardPadding)
                .background(Palette.surfaceLive.color, in: .rect(cornerRadius: Radii.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.card)
                        .strokeBorder(Palette.nuzlocke.alpha(0x44), lineWidth: 1)
                )
                .contentShape(.rect)
            }
            .accessibilityHint("Opens the squad you are walking into")
        } else if !model.timeline.isEmpty {
            Text("Every seeded checkpoint is beaten.")
                .font(Typography.meta)
                .foregroundStyle(Palette.textMuted.color)
                .padding(Metrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface.color, in: .rect(cornerRadius: Radii.card))
        }
    }

    // MARK: Coverage

    /// "Nothing in your party resists Fighting. Gastly and Staravia do, from the box."
    ///
    /// Absent when the party covers everything the next checkpoint throws, which is the common
    /// case — this is a warning, not a permanent panel, and a row saying "you're fine" every time
    /// would train you to stop reading it.
    @ViewBuilder
    private var coverageCard: some View {
        let gaps = model.coverage
        if !gaps.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("Coverage warning")
                    .font(Typography.blockLabel)
                    .tracking(Typography.blockLabelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.danger.color)

                ForEach(gaps) { gap in
                    HStack(alignment: .top, spacing: 9) {
                        Text(gap.type.displayName)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.textPrimary.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                gap.type.swatch.alpha(0x3D),
                                in: .rect(cornerRadius: Radii.typeChip)
                            )
                        Text(sentence(for: gap))
                            .font(Typography.meta)
                            .foregroundStyle(Palette.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface.color, in: .rect(cornerRadius: Radii.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.card)
                    .strokeBorder(Palette.danger.alpha(0x44), lineWidth: 1)
            )
        }
    }

    /// `ListFormatter` rather than a hand-rolled join: it gets the Oxford comma and the "and"
    /// right for one, two and many, in the user's locale.
    private func sentence(for gap: NuzlockeModel.CoverageGap) -> String {
        let opening = "Nothing in your party resists \(gap.type.displayName)."
        guard !gap.benchResisters.isEmpty else { return opening }
        let names = gap.benchResisters.map { $0.nickname ?? model.speciesName(for: $0) }
        let list = ListFormatter.localizedString(byJoining: names)
        return "\(opening) \(list) \(names.count == 1 ? "does" : "do"), from the box."
    }

    // MARK: Party

    /// The living roster, with the graveyard count beside it — the two numbers a Nuzlocke run
    /// actually turns on.
    private var partyStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Party")
                    .font(Typography.blockLabel)
                    .tracking(Typography.blockLabelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textMuted.color)
                Spacer(minLength: 0)
                // The counts were the whole representation of the box and the graveyard. They
                // are the way into the roster now, where those Pokémon actually exist.
                Button { showingRoster = true } label: {
                    HStack(spacing: 8) {
                        if model.graveyard.isEmpty, model.boxed.isEmpty {
                            // Nothing lost and nothing boxed yet: the counts would both be
                            // hidden, leaving a bare chevron with no idea what it opens.
                            Text("Roster")
                                .foregroundStyle(Palette.textMuted.color)
                        }
                        if !model.graveyard.isEmpty {
                            Text("\(model.graveyard.count) in graveyard")
                                .foregroundStyle(Palette.danger.color)
                        }
                        if !model.boxed.isEmpty {
                            Text("\(model.boxed.count) boxed")
                                .foregroundStyle(Palette.textMuted.color)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Palette.textFaint.color)
                    }
                    .font(Typography.hint)
                    .contentShape(.rect)
                }
                .accessibilityLabel("Open the roster")
            }

            if model.party.isEmpty {
                Text("Nothing alive in the party yet.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textFaint.color)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.party) { member in
                            partyTile(member)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface.color, in: .rect(cornerRadius: Radii.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.card)
                .strokeBorder(Palette.hairline.color, lineWidth: 1)
        )
    }

    /// A menu rather than a button: the three moves a party member can make (box it, bury it) are
    /// destructive-ish and rare, and a swipe action has nowhere to live in a horizontal strip.
    private func partyTile(_ member: NuzlockeEncounterLog) -> some View {
        Menu {
            Button("Send to box") { Task { await model.move(member, to: .boxed) } }
            Button("It fainted", role: .destructive) {
                Task { await model.move(member, to: .fainted) }
            }
        } label: {
            VStack(spacing: 4) {
                DexSprite(
                    pokemonID: member.pokemonID ?? 0,
                    size: 46,
                    served: model.option(for: member)?.spriteURL
                )
                Text(member.nickname ?? model.speciesName(for: member))
                    .font(Typography.tileSub)
                    .foregroundStyle(Palette.textPrimary.color)
                    .lineLimit(1)
            }
            .frame(width: 72)
            .padding(.vertical, 9)
            .background(Palette.surfaceRaised.color, in: .rect(cornerRadius: Radii.tile))
            .contentShape(.rect)
        }
        .accessibilityLabel(
            "\(member.nickname ?? model.speciesName(for: member)), in the party")
    }

    // MARK: Timeline rows

    /// One route. Unlogged and current is the call to action; logged shows what came of it.
    private func locationRow(_ entry: NuzlockeTimelineEntry) -> some View {
        let logged = model.log(at: entry.slug)
        let isCurrent = model.currentSlug == entry.slug
        return Button { loggingAt = entry } label: {
            HStack(spacing: 12) {
                if let logged, let option = model.option(for: logged) {
                    DexSprite(pokemonID: option.pokemonID, size: 44, served: option.spriteURL)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radii.sprite(44))
                            .fill(Palette.surfaceRaised.color)
                        Image(systemName: isCurrent ? "location.fill" : "circle.dashed")
                            .font(.system(size: 15))
                            .foregroundStyle(
                                (isCurrent ? Palette.nuzlocke : Palette.textFaint).color)
                    }
                    .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(rowTitle(entry, logged))
                        .font(Typography.listTitle)
                        .foregroundStyle(Palette.textPrimary.color)
                        .lineLimit(1)
                    Text(rowMeta(entry, logged, isCurrent: isCurrent))
                        .font(Typography.tileSub)
                        .foregroundStyle(Palette.textMuted.color)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let logged {
                    let outcome = EncounterOutcome(logged)
                    Text(outcome.label)
                        .font(Typography.tag)
                        .foregroundStyle(outcome.tint.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(outcome.tint.alpha(0x1F), in: .rect(cornerRadius: Radii.tag))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Palette.surface.color, in: .rect(cornerRadius: Radii.row))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.row)
                    .strokeBorder(
                        isCurrent ? Palette.nuzlocke.alpha(0x55) : Palette.hairline.color,
                        lineWidth: isCurrent ? 2 : 1
                    )
            )
            .contentShape(.rect)
        }
    }

    private func rowTitle(_ entry: NuzlockeTimelineEntry, _ logged: NuzlockeEncounterLog?) -> String {
        guard let logged, logged.pokemonID != nil else { return entry.name }
        let species = model.speciesName(for: logged)
        guard let nickname = logged.nickname, !nickname.isEmpty else { return species }
        return "\(species) “\(nickname)”"
    }

    private func rowMeta(
        _ entry: NuzlockeTimelineEntry, _ logged: NuzlockeEncounterLog?, isCurrent: Bool
    ) -> String {
        guard let logged else {
            return isCurrent ? "Log your encounter · you're here" : "Unlogged"
        }
        var parts = [entry.name, logged.status]
        if logged.isDupe { parts.append("dupe") }
        return parts.joined(separator: " · ")
    }

    /// A boss checkpoint, with the beaten tick on the row itself — tapping the row opens the
    /// squad, tapping the tick marks it down.
    private func checkpointRow(_ entry: NuzlockeTimelineEntry) -> some View {
        let done = model.isBeaten(entry.slug)
        return HStack(spacing: 12) {
            Button { Task { await model.setBoss(entry.slug, beaten: !done) } } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle((done ? Palette.nuzlocke : Palette.textFaint).color)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("\(entry.name) beaten")
            .accessibilityAddTraits(done ? [.isSelected] : [])

            Button { openBoss = entry } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.name)
                            .font(Typography.listTitle)
                            .foregroundStyle(Palette.textPrimary.color)
                        Text(
                            [entry.bossTitle, entry.place].compactMap { $0 }
                                .joined(separator: " · ")
                        )
                        .font(Typography.tileSub)
                        .foregroundStyle(Palette.textMuted.color)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let cap = entry.levelCap {
                        Text("CAP \(cap)")
                            .font(Typography.tag)
                            .foregroundStyle(Palette.nuzlocke.color)
                    }
                }
                .contentShape(.rect)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Palette.surfaceRaised.color, in: .rect(cornerRadius: Radii.row))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.row)
                .strokeBorder(
                    done ? Palette.nuzlocke.alpha(0x33) : Palette.border.color, lineWidth: 1)
        )
    }
}

// MARK: - Button style

/// Hunt's ``GoldButtonStyle`` in Nuzlocke blue. A run screen never shows gold.
struct BlueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.primaryButton)
            .foregroundStyle(Palette.onAccent.color)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.controlHeight)
            .background(Palette.nuzlocke.color, in: .rect(cornerRadius: Radii.control))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

// MARK: - Run picker

/// Every run the caller owns. Switching is the only thing this does — a run is never deleted,
/// so there is nothing else to offer here.
struct RunPickerSheet: View {
    @State var model: NuzlockeModel
    @Environment(\.dismiss) private var dismiss
    @State private var startingRun = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your runs")
                    .font(Typography.sheetTitle)
                    .tracking(Typography.sheetTitleTracking)
                    .foregroundStyle(Palette.textPrimary.color)
                    .padding(.bottom, 4)

                ForEach(model.runs) { candidate in
                    Button {
                        Task { await model.select(candidate) }
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(candidate.gameTitle ?? "Run")
                                    .font(Typography.segmentOn)
                                    .foregroundStyle(Palette.textPrimary.color)
                                Text(
                                    candidate.startedAt
                                        .formatted(date: .abbreviated, time: .omitted)
                                )
                                .font(Typography.tileSub)
                                .foregroundStyle(Palette.textMuted.color)
                            }
                            Spacer(minLength: 0)
                            Text(candidate.isActive ? "Active" : "Ended")
                                .font(Typography.tag)
                                .foregroundStyle(
                                    (candidate.isActive ? Palette.nuzlocke : Palette.textFaint)
                                        .color)
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity)
                        .background(Palette.surface.color, in: .rect(cornerRadius: Radii.block))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radii.block)
                                .strokeBorder(
                                    candidate.id == model.run?.id
                                        ? Palette.nuzlocke.alpha(0x55) : Palette.hairline.color,
                                    lineWidth: candidate.id == model.run?.id ? 2 : 1
                                )
                        )
                        .contentShape(.rect)
                    }
                }

                Button("Start another run") { startingRun = true }
                    .buttonStyle(BlueButtonStyle())
                    .padding(.top, 10)

                if let run = model.run, run.isActive {
                    Button("End this run") {
                        Task { await model.setRunStatus(.ended) }
                        dismiss()
                    }
                    .font(Typography.segmentOff)
                    .foregroundStyle(Palette.danger.color)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
            }
            .padding(18)
        }
        .background(Palette.sheet.color)
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.sheet.color)
        .sheet(isPresented: $startingRun) {
            NewRunSheet(model: model)
        }
    }
}

// MARK: - Checkpoint sheet

/// What the next boss is bringing: the squad, levels, abilities and movesets the seed carries.
struct CheckpointSheet: View {
    @State var model: NuzlockeModel
    let boss: NuzlockeTimelineEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(boss.name)
                        .font(Typography.sheetTitle)
                        .tracking(Typography.sheetTitleTracking)
                        .foregroundStyle(Palette.textPrimary.color)
                    Text(
                        [boss.bossTitle, boss.place].compactMap { $0 }.joined(separator: " · ")
                    )
                    .font(Typography.meta)
                    .foregroundStyle(Palette.textSecondary.color)
                    if let cap = boss.levelCap {
                        Text("Level cap \(cap)")
                            .font(Typography.statStrong)
                            .foregroundStyle(Palette.nuzlocke.color)
                    }
                }

                ForEach(boss.squad ?? []) { member in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            DexSprite(
                                pokemonID: member.pokemonID, size: 48, served: member.spriteURL)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(member.pokemonName.capitalized)
                                    .font(Typography.listTitle)
                                    .foregroundStyle(Palette.textPrimary.color)
                                Text("Lv \(member.level) · \(member.ability)")
                                    .font(Typography.tileSub)
                                    .foregroundStyle(Palette.textMuted.color)
                            }
                            Spacer(minLength: 0)
                        }
                        if let moves = member.moves, !moves.isEmpty {
                            // The same wrapping layout the species sheet uses for type chips.
                            FlowRow(spacing: 6) {
                                ForEach(moves, id: \.name) { move in
                                    moveChip(move)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surfaceBlock.color, in: .rect(cornerRadius: Radii.block))
                }

                Button(model.isBeaten(boss.slug) ? "Mark not beaten" : "Beaten") {
                    Task { await model.setBoss(boss.slug, beaten: !model.isBeaten(boss.slug)) }
                    dismiss()
                }
                .buttonStyle(BlueButtonStyle())
                .padding(.top, 6)
            }
            .padding(18)
        }
        .background(Palette.sheet.color)
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.sheet.color)
    }

    /// One move, tinted by its type. The seed capitalises move types ("Flying") and
    /// `PokemonType(slug:)` lowercases before matching, so they resolve with no translation step.
    private func moveChip(_ move: NuzlockeBossMove) -> some View {
        let swatch = PokemonType(slug: move.type)?.swatch ?? Palette.textFaint
        return Text(move.name)
            .font(Typography.tileSub)
            .foregroundStyle(Palette.textPrimary.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(swatch.alpha(0x2E), in: .rect(cornerRadius: Radii.typeChip))
    }
}
