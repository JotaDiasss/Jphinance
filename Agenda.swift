import SwiftUI

enum ReportKind: String {
    case fixed = "Fixos mensais", total = "Gastos do mês", difference = "Comparação mensal"
    var icon: String {
        switch self {
        case .fixed: return "repeat"
        case .total: return "wallet.pass"
        case .difference: return "chart.bar.xaxis"
        }
    }
}

struct ExpenseReport: Identifiable {
    let id = UUID()
    let kind: ReportKind
    let month: Date
}

struct ReportSheet: View {
    let report: ExpenseReport
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(report.kind.rawValue, systemImage: report.kind.icon)
                        .font(.title2.bold()).foregroundStyle(Color.mintLeaf)
                    Spacer()
                    Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                monthSection(report.month)
                if report.kind == .difference { monthSection(BookDate.shift(report.month, by: -1)) }
            }.padding(22)
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 500, minHeight: 330, idealHeight: 470)
        #endif
        .buttonStyle(FinanceButtonStyle())
    }
    func monthSection(_ month: Date) -> some View {
        let entries = store.entries(in: month).filter { report.kind != .fixed || $0.repeatsMonthly }
        return Panel {
            HStack {
                Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                Spacer()
                Text(money(entries.reduce(0) { $0 + $1.cents })).font(.headline.monospacedDigit())
            }
            Divider()
            if entries.isEmpty { Text("Nenhum gasto neste período.").foregroundStyle(.secondary) }
            ForEach(entries) { e in
                HStack(spacing: 12) {
                    Text(e.date, format: .dateTime.day()).font(.caption.monospacedDigit()).foregroundStyle(Color.mintLeaf)
                        .frame(width: 28, height: 28).background(Color.pine, in: Circle())
                    Text(e.title)
                    Spacer()
                    Text(money(e.cents)).monospacedDigit()
                }
            }
        }
    }
}

struct AgendaCalendar: View {
    @Binding var date: Date
    @Binding var wholeMonth: Bool
    let entries: [Expense]
    var body: some View {
        Panel {
            Text("Data da agenda").font(.headline).foregroundStyle(.secondary)
            MonthGrid(monthDate: $date, selected: date, entries: entries) { day in
                date = day
                wholeMonth = false
            }
            Divider()
            Picker("Período dos lançamentos", selection: $wholeMonth) {
                Text("Dia selecionado").tag(false)
                Text("Mês inteiro").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
}

struct MonthGrid: View {
    @Binding var monthDate: Date
    let selected: Date
    var entries: [Expense] = []
    let choose: (Date) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var month: Int { BookDate.month(monthDate) }
    private var first: Date { BookDate.date(in: month, day: 1) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let week = ["D", "S", "T", "Q", "Q", "S", "S"]
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(monthDate, format: .dateTime.month(.wide).year()).font(.headline)
                Spacer()
                arrow(-1)
                Button("Hoje") { let today = Date(); monthDate = today; choose(today) }
                arrow(1)
            }
            let count = BookDate.cal.range(of: .day, in: .month, for: first)!.count
            let offset = BookDate.cal.component(.weekday, from: first) - 1
            let marked = Set(entries.map { BookDate.stamp($0.date) })
            let firstDaySlot = week.count + offset
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<(firstDaySlot + count), id: \.self) { slot in
                    if slot < week.count {
                        Text(week[slot]).font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
                    } else if slot < firstDaySlot {
                        Color.clear.frame(height: 32).accessibilityHidden(true)
                    } else {
                        let day = slot - firstDaySlot + 1
                        let stamp = month * 100 + day
                        let cell = BookDate.date(in: month, day: day)
                        DayChip(day: day, selected: stamp == BookDate.stamp(selected), today: stamp == BookDate.stamp(Date()),
                                marked: marked.contains(stamp)) { choose(cell) }
                            .accessibilityLabel(Text(cell, format: .dateTime.day().month(.wide).year()))
                    }
                }
            }
        }.buttonStyle(FinanceButtonStyle())
    }
    private func arrow(_ step: Int) -> some View {
        Button {
            let target = BookDate.month(BookDate.shift(monthDate, by: step))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                monthDate = BookDate.date(in: target, day: BookDate.cal.component(.day, from: monthDate))
            }
        } label: { Image(systemName: step < 0 ? "chevron.left" : "chevron.right") }
        .accessibilityLabel(step < 0 ? "Mês anterior" : "Próximo mês")
    }
}

struct DayChip: View {
    let day: Int
    let selected: Bool
    var today = false
    var marked = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                Circle().fill(selected ? Color.mintLeaf : .clear)
                if today { Circle().strokeBorder(Color.mintLeaf, lineWidth: 1) }
                Text(String(day)).font(.body.weight(selected || today ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(selected ? Color.carbon : Color.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if marked { Circle().fill(selected ? Color.carbon : Color.mintLeaf).frame(width: 4, height: 4).padding(.bottom, 2) }
            }.frame(width: 32, height: 32).frame(maxWidth: .infinity)
        }
        .buttonStyle(FinanceButtonStyle(appearance: .navigation))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
