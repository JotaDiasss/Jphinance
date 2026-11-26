import SwiftUI
import AppKit

@main @MainActor struct JphinanceApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup("Jphinance") {
            Dashboard().environmentObject(store)
                .environment(\.locale, Locale(identifier: "pt_BR"))
                .preferredColorScheme(.dark)
                .tint(.mintLeaf)
                #if os(macOS)
                .frame(minWidth: 550, minHeight: 460)
                #endif
        }
    }
}
extension Color {
    static let mintLeaf = Color(red: 0.41, green: 0.75, blue: 0.56)
    static let pine = Color(red: 0.085, green: 0.205, blue: 0.145)
    static let carbon = Color(red: 0.038, green: 0.049, blue: 0.045)
}
struct FinanceButtonStyle: ButtonStyle {
    enum Appearance { case standard, primary, navigation }
    let appearance: Appearance
    init(appearance: Appearance = .standard) { self.appearance = appearance }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if appearance == .primary {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.carbon)
                .padding(.horizontal, 16).frame(minHeight: 34)
                .background(hovering && enabled ? Color(red: 0.50, green: 0.80, blue: 0.62) : Color.mintLeaf, in: Capsule())
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
        } else {
            let navigation = appearance == .navigation
            let fill: Color = navigation ? .clear : .white.opacity(0.09)
            configuration.label
                .padding(.horizontal, navigation ? 0 : 10)
                .padding(.vertical, navigation ? 0 : 5)
                .foregroundStyle(Color.primary)
                .background(fill, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: navigation ? 14 : 8)
                        .fill(Color.mintLeaf.opacity(hovering && enabled ? 0.11 : 0))
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .offset(y: hovering && enabled && !reduceMotion && !configuration.isPressed ? -1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
                .opacity(!enabled ? 0.45 : (configuration.isPressed ? 0.78 : 1))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
        }
    }
}
enum Page: String, CaseIterable {
    case home = "Resumo", agenda = "Agenda", monthly = "Gastos fixos", goal = "Meta", savings = "Caixinhas", settings = "Ajustes"
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .agenda: return "calendar"
        case .monthly: return "repeat"
        case .goal: return "scope"
        case .savings: return "archivebox"
        case .settings: return "slider.horizontal.3"
        }
    }
}
enum Editor: Identifiable {
    case expense(Expense?), budget, goal
    var id: String {
        switch self { case .expense(let e): return e?.id.uuidString ?? "expense"; case .budget: return "budget"; case .goal: return "goal" }
    }
}
struct FinanceGlass: View {
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            if reduceTransparency {
                shape.fill(Color(red: 0.095, green: 0.14, blue: 0.12))
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.carbon.opacity(0.35))
                shape.fill(LinearGradient(stops: [
                    .init(color: Color.white.opacity(0.042), location: 0),
                    .init(color: Color.mintLeaf.opacity(0.022), location: 0.28),
                    .init(color: Color.carbon.opacity(0.065), location: 0.65),
                    .init(color: Color.mintLeaf.opacity(0.025), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.055), Color.mintLeaf.opacity(0.095)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 4)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct Panel<Inner: View>: View {
    let content: Inner
    init(@ViewBuilder content: () -> Inner) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(FinanceGlass(radius: 22))
    }
}
struct Dashboard: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var forward = true
    @State private var page = Page.home
    @State private var editor: Editor?
    @State private var date = Date()
    @State private var wholeMonth = true
    @State private var removing: Expense?
    @State private var confirmingGoalRemoval = false
    @State private var report: ExpenseReport?
    @State private var link = ""
    @State private var pairing = false
    var monthRows: [Expense] { store.entries(in: Date()) }
    var spent: Int { monthRows.reduce(0) { $0 + $1.cents } }
    func select(_ next: Page) {
        guard next != page else { return }
        forward = Page.allCases.firstIndex(of: next)! > Page.allCases.firstIndex(of: page)!
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.26)) { page = next }
    }
    private static let sidebarWidth: CGFloat = 224
    private static let coin = Bundle.main.url(forResource: "JPCoin", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    var wordmark: some View {
        HStack(spacing: 10) {
            if let coin = Self.coin {
                Image(nsImage: coin).resizable().interpolation(.high)
                    .scaledToFit().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            Text("Jphinance")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }.accessibilityElement(children: .combine)
    }
    var body: some View {
        GeometryReader { geo in
            let rail = geo.size.width >= 980
            ZStack {
                Color.carbon.ignoresSafeArea()
                RadialGradient(colors: [Color.mintLeaf.opacity(0.075), Color.pine.opacity(0.28), .clear], center: .topTrailing, startRadius: 10, endRadius: 610).ignoresSafeArea()
                RadialGradient(colors: [Color.pine.opacity(0.36), .clear], center: .bottomLeading, startRadius: 15, endRadius: 460).ignoresSafeArea()
                HStack(alignment: .top, spacing: 0) {
                    if rail {
                        VStack(alignment: .leading, spacing: 24) {
                            wordmark
                            ForEach(Page.allCases, id: \.self) { item in nav(item, tall: false) }
                            Spacer()
                        }.padding(22).frame(width: Self.sidebarWidth).background(.ultraThinMaterial)
                    }
                    ZStack(alignment: .top) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 23) {
                                if !rail { wordmark }
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if page == .home { Text(Date(), format: .dateTime.month(.wide).year()).textCase(.uppercase).tracking(1.4).font(.caption.weight(.semibold)).foregroundStyle(Color.mintLeaf) }
                                        Text(page.rawValue).font(.system(size: 37, weight: .semibold, design: .rounded))
                                    }
                                    Spacer()
                                    if page == .home || page == .agenda || page == .monthly {
                                        Button { editor = .expense(nil) } label: { Label(page == .monthly ? "Gasto fixo" : "Gasto", systemImage: "plus") }.buttonStyle(FinanceButtonStyle(appearance: .primary))
                                    }
                                }
                                content(wide: geo.size.width - (rail ? Self.sidebarWidth : 0) >= 680)
                            }.padding(geo.size.width > 680 ? 30 : 17).frame(maxWidth: 1220)
                        }
                        .id(page)
                        .transition(reduceMotion ? .identity : .push(from: forward ? .trailing : .leading))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .safeAreaInset(edge: .bottom) {
                        if !rail {
                            HStack { ForEach(Page.allCases, id: \.self) { item in nav(item, tall: true) } }
                                .padding(6).background(.regularMaterial, in: Capsule()).padding(.horizontal, 12).padding(.bottom, 4)
                        }
                    }
                }
            }
        }
        .buttonStyle(FinanceButtonStyle())
        .sheet(item: $editor) { item in EntryEditor(mode: item, startMonthly: page == .monthly).environmentObject(store) }
        .sheet(item: $report) { selection in
            ReportSheet(report: selection).environmentObject(store)
        }
        .confirmationDialog(removing?.repeatsMonthly == true ? "Encerrar este gasto mensal?" : "Excluir este gasto?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { e in
            Button("Excluir " + e.title, role: .destructive) { store.removeExpense(e) }
            Button("Cancelar", role: .cancel) { }
        } message: { item in
            Text(item.repeatsMonthly ? "A cobrança sai deste mês e dos próximos. Os meses anteriores continuam no histórico." : "Este lançamento será excluído.")
        }
        .alert("Jphinance", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("OK") { store.message = nil } } message: { Text(store.message ?? "") }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.sync()
                do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            }
        }
    }
    func nav(_ item: Page, tall: Bool) -> some View {
        Button { select(item) } label: {
            Group {
                if tall {
                    VStack(spacing: 3) { Image(systemName: item.icon); Text(item.rawValue).font(.caption2) }
                } else { Label(item.rawValue, systemImage: item.icon) }
            }.frame(maxWidth: .infinity, minHeight: 43, alignment: tall ? .center : .leading)
            .padding(.horizontal, tall ? 1 : 10)
            .background(page == item ? Color.mintLeaf.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(page == item ? Color.mintLeaf : .white.opacity(0.75))
        }.buttonStyle(FinanceButtonStyle(appearance: .navigation))
    }
    @ViewBuilder func content(wide: Bool) -> some View {
        switch page {
        case .home:
            summaryTiles(for: Date(), wide: wide)
            if wide {
                HStack(alignment: .top, spacing: 18) { VStack(spacing: 18) { hero; savingsSummary; goalCard }; VStack(spacing: 18) { recent; categories } }
            } else { hero; savingsSummary; recent; goalCard; categories }
        case .agenda:
            summaryTiles(for: date, wide: wide)
            if wide { HStack(alignment: .top, spacing: 18) { picker; journal } } else { picker; journal }
        case .monthly:
            monthlyCards
        case .goal:
            if wide { HStack(alignment: .top, spacing: 18) { goalCard; advice } } else { goalCard; advice }
        case .savings:
            SavingsPage()
        case .settings:
            if wide { HStack(alignment: .top, spacing: 18) { budgetCard; syncCard } } else { budgetCard; syncCard }
        }
    }
    var savingsSummary: some View {
        SavingsSummary { select(.savings) }
    }
    var hero: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("Disponível no mês", systemImage: "wallet.pass").font(.subheadline.weight(.medium))
            Text(money(store.budget - spent)).font(.system(size: 42, weight: .semibold, design: .rounded)).minimumScaleFactor(0.48).lineLimit(1).monospacedDigit()
            ProgressView(value: min(1, Double(spent)/Double(max(1,store.budget)))).tint(.mintLeaf)
            HStack { metric("Orçamento", money(store.budget)); Spacer(); metric("Gastos", money(spent)) }
            Button("Ajustar orçamento") { editor = .budget }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [Color.pine, Color(red: 0.13, green: 0.275, blue: 0.185), Color.pine], startPoint: .bottomLeading, endPoint: .topTrailing)
                ZStack { ForEach(0..<5) { i in Ellipse().stroke(Color.mintLeaf.opacity(0.16), lineWidth: 1).frame(width: CGFloat(130+i*17), height: CGFloat(95+i*13)) } }
                    .rotationEffect(.degrees(-38)).offset(x: 66, y: -46).accessibilityHidden(true)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.13)))
    }
    func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).foregroundStyle(.secondary).font(.caption); Text(value).font(.headline).monospacedDigit() }
    }
    var recent: some View {
        Panel { Text("Últimos gastos").font(.title3.bold())
            if store.latestEntries.isEmpty { Text("Seus lançamentos aparecem aqui.").foregroundStyle(.secondary) }
            ForEach(store.latestEntries, id: \.occurrenceKey) { e in row(e) }
            Button("Abrir agenda") { select(.agenda) }
        }
    }
    func row(_ e: Expense) -> some View {
        HStack {
            Image(systemName: e.repeatsMonthly ? "repeat" : e.category.symbol).foregroundStyle(Color.mintLeaf).frame(width: 34, height: 34).background(Color.pine,in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) { Text(e.title).font(.body.weight(.medium)); Text(e.date, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Text(money(e.cents)).font(.subheadline.monospacedDigit())
            if !e.repeatsMonthly {
                Menu { Button("Editar") { editor = .expense(e) }; Button("Excluir", role: .destructive) { removing = e } } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Opções de " + e.title)
            }
        }
    }
    var categories: some View {
        var totals: [Category: Int] = [:]
        for expense in monthRows {
            totals[expense.category, default: 0] += expense.cents
        }
        let ranked: [Category] = totals.keys.sorted { a, b in
            let first: Int = totals[a] ?? 0
            let second: Int = totals[b] ?? 0
            if first == second { return a.rawValue < b.rawValue }
            return first > second
        }
        return Panel { Text("Por categoria").font(.title3.bold())
            if totals.isEmpty { Text("Registre um gasto para ver a distribuição do mês.").foregroundStyle(.secondary) }
            ForEach(ranked, id: \.self) { cat in
                HStack { Label(cat.label, systemImage: cat.symbol); Spacer(); Text(money(totals[cat, default: 0])) }
                ProgressView(value: Double(totals[cat, default: 0])/Double(max(1, spent))).tint(.mintLeaf)
            }
        }
    }
    var picker: some View {
        AgendaCalendar(date: $date, wholeMonth: $wholeMonth, entries: store.entries(in: date))
    }
    var journal: some View {
        let items = store.entries(in: date).filter { wholeMonth || BookDate.stamp($0.date) == BookDate.stamp(date) }
        return Panel {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lançamentos").font(.title3.bold())
                    if wholeMonth { Text(date, format: .dateTime.month(.wide).year()).foregroundStyle(.secondary) }
                    else { Text(date, format: .dateTime.day().month(.wide)).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(money(items.reduce(0) { $0 + $1.cents })).font(.headline.monospacedDigit())
            }
            Divider()
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "list.bullet.rectangle").font(.title2).foregroundStyle(Color.mintLeaf)
                    Text("Nenhum gasto neste período.").foregroundStyle(.secondary)
                    Button("Registrar gasto") { editor = .expense(nil) }
                }.padding(.vertical, 10)
            }
            ForEach(items) { e in row(e) }
        }
    }
    func summaryTiles(for selected: Date, wide: Bool) -> some View {
        let items = store.entries(in: selected)
        let total = items.reduce(0) { $0 + $1.cents }
        let fixed = items.filter { $0.repeatsMonthly }.reduce(0) { $0 + $1.cents }
        let previous = store.entries(in: BookDate.shift(selected, by: -1)).reduce(0) { $0 + $1.cents }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: wide ? 3 : 1)
        return LazyVGrid(columns: columns, spacing: 12) {
            reportTile(.fixed, amount: fixed, month: selected)
            reportTile(.total, amount: total, month: selected)
            reportTile(.difference, amount: total - previous, month: selected)
        }
    }
    func reportTile(_ kind: ReportKind, amount: Int, month: Date) -> some View {
        Button { report = ExpenseReport(kind: kind, month: month) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: kind.icon).foregroundStyle(Color.mintLeaf); Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                Text(kind.rawValue).font(.subheadline.weight(.medium))
                Text((kind == .difference && amount > 0 ? "+" : "") + money(amount))
                    .font(.title2.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                if kind == .difference { Text("Em relação ao mês anterior").font(.caption).foregroundStyle(.secondary) }
                else { Text(month, format: .dateTime.month(.wide).year()).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(FinanceGlass(radius: 18))
        }.buttonStyle(FinanceButtonStyle(appearance: .navigation))
    }
    var monthlyCards: some View {
        let active = store.activeMonthly
        let now = Date()
        return VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Total deste mês").foregroundStyle(.secondary); Spacer()
                Text(money(monthRows.filter { $0.repeatsMonthly }.reduce(0) { $0 + $1.cents })).font(.title2.bold().monospacedDigit())
            }
            if active.isEmpty {
                Panel { Label("Nenhum gasto fixo cadastrado", systemImage: "repeat").font(.headline)
                    Text("Cadastre uma cobrança e ela aparecerá na agenda de cada mês.").foregroundStyle(.secondary)
                    Button("Adicionar gasto fixo") { editor = .expense(nil) }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), spacing: 16)], spacing: 16) {
                ForEach(active) { e in
                    Panel {
                        Label(e.title, systemImage: "repeat").font(.headline)
                        Text(e.category.label).font(.caption).foregroundStyle(.secondary)
                        Text(money(e.cents)).font(.title2.bold().monospacedDigit())
                        if let rate = e.rate(in: BookDate.month(e.date)) {
                            Text("Todo mês, dia " + String(rate.day)).foregroundStyle(.secondary)
                        }
                        if BookDate.month(e.date) > BookDate.month(now) {
                            Text("Início: " + e.date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "pt_BR")))).font(.caption)
                        }
                        HStack { Button("Editar") { editor = .expense(e) }
                            Button("Excluir", role: .destructive) { removing = e }
                        }
                    }
                }
            }
        }
    }
    var goalCard: some View {
        Panel { Label("Minha meta", systemImage: "scope").foregroundStyle(Color.mintLeaf)
            if let g = store.goal {
                Text(g.title).font(.title2.bold())
                if let notes = g.notes, !notes.isEmpty { Text(notes).fixedSize(horizontal: false, vertical: true) }
                Text(g.deadline, format: .dateTime.day().month(.wide).year()).foregroundStyle(.secondary)
                ProgressView(value: min(1, Double(g.saved)/Double(max(1,g.target)))).tint(.mintLeaf)
                HStack { metric("Guardado",money(g.saved)); Spacer(); metric("Objetivo",money(g.target)) }
                HStack {
                    Button("Atualizar meta") { editor = .goal }
                    Button("Excluir meta", role: .destructive) { confirmingGoalRemoval = true }
                        .confirmationDialog("Excluir esta meta?", isPresented: $confirmingGoalRemoval, titleVisibility: .visible) {
                            Button("Excluir meta", role: .destructive) { store.set("goal", .deleted) }
                            Button("Cancelar", role: .cancel) {}
                        } message: { Text("O objetivo e seu progresso serão removidos. O saldo das caixinhas é independente.") }
                }
            } else { Text("Quanto você quer guardar?").font(.title3.bold()); Button("Criar meta") { editor = .goal } }
        }
    }
    @ViewBuilder var advice: some View {
        if let g = store.goal {
            let p = Plan(goal: g, budget: store.budget, expenses: monthRows)
            Panel { Text("Plano de economia").font(.title3.bold())
                if p.remaining == 0 { Text("Meta alcançada.") }
                else if p.expired { Text("O prazo terminou. Atualize a data para recalcular.") }
                else {
                    metric("Falta guardar",money(p.remaining)); metric("Média mensal necessária",money(p.average))
                    if store.budget == 0 { Button("Definir orçamento") { editor = .budget } }
                    else {
                        Text("Reserve " + money(p.now) + " neste mês.")
                        if p.months > 1 { Text("Nos meses seguintes, reserve " + money(p.future) + " por mês.")
                            if !p.cuts.isEmpty { Text("Reduções mensais sugeridas").font(.headline)
                                ForEach(p.cuts.indices, id: \.self) { i in HStack { Text(p.cuts[i].0.label); Spacer(); Text(money(p.cuts[i].1)) } }
                            }
                        }
                        if p.shortage > 0 { Text("A meta não cabe no orçamento projetado. Faltam " + money(p.shortage) + (p.months > 1 ? " por mês, mesmo com os cortes." : " até o prazo.")) }
                        Text("Projeção baseada nos gastos registrados neste mês. Os gastos fixos ficam fora dos cortes.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    var budgetCard: some View {
        Panel { metric("Orçamento mensal", money(store.budget)); Button("Editar orçamento") { editor = .budget } }
    }
    var syncCard: some View {
        Panel { Label("Sincronização", systemImage: "arrow.triangle.2.circlepath").font(.title3.bold())
            Text(store.status)
            if store.connected { Button("Sincronizar agora") { Task { await store.sync() } } }
            else {
                Text("Cole o mesmo link privado nos três aparelhos.").foregroundStyle(.secondary)
                SecureField("Link privado", text: $link).textFieldStyle(.roundedBorder)
                Button(pairing ? "Conectando…" : "Conectar") { pairing = true; Task { if await store.pair(link) { link = "" }; pairing = false } }.disabled(link.isEmpty || pairing)
            }
        }
    }
}
