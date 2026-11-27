import SwiftUI
struct EntryEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presented = false
    let mode: Editor
    var startMonthly = false
    @State private var category = Category.other
    @State private var dueDay = 1
    @State private var title = ""
    @State private var notes = ""
    @State private var amount = ""
    @State private var saved = "0"
    @State private var date = Date()
    @State private var fixed = false
    @State private var warning = ""
    @State private var loaded = false
    var editingSeries: Bool {
        if case .expense(let e) = mode { return e?.repeatsMonthly == true }
        return false
    }
    var heading: String {
        switch mode { case .goal: return "Minha meta"; case .budget: return "Orçamento mensal"; case .expense(let e): return e == nil ? "Novo gasto" : "Editar gasto" }
    }
    func amountField(_ name: String, _ value: Binding<String>) -> some View {
        TextField(name, text: value)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }
    var body: some View {
        NavigationStack {
            Form {
                switch mode {
                case .expense:
                    Section("Gasto") {
                        TextField("Descrição", text: $title)
                        amountField("Valor (R$)", $amount)
                        Picker("Categoria", selection: $category) {
                            ForEach(Category.selectable) { item in Label(item.label, systemImage: item.symbol).tag(item) }
                        }
                        LedgerDateField(date: $date, dueDay: $dueDay, monthlyDay: editingSeries)
                        if editingSeries {
                            Text("Alterações valem a partir deste mês ou do início da cobrança, se for posterior.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Toggle("Repetir todo mês", isOn: $fixed).toggleStyle(.switch)
                        }
                    }
                case .budget:
                    Section("Limite mensal") { amountField("Valor (R$)", $amount) }
                case .goal:
                    Section("Objetivo") {
                        TextField("Nome da meta", text: $title)
                        TextField("Descrição (opcional)", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                        amountField("Valor da meta (R$)", $amount)
                        amountField("Já guardado (R$)", $saved)
                        LedgerDateField(date: $date, dueDay: .constant(1), monthlyDay: false, label: "Prazo")
                    }
                }
                if !warning.isEmpty { Text(warning).foregroundStyle(Color.mintLeaf) }
            }
            .formStyle(.grouped)
            .scaleEffect(presented || reduceMotion ? 1 : 0.965, anchor: .top)
            .opacity(presented || reduceMotion ? 1 : 0)
            .navigationTitle(heading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar") { submit() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 390, minHeight: 370)
        #endif
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { presented = true }
            guard !loaded else { return }; loaded = true
            switch mode {
            case .budget: amount = display(store.budget)
            case .goal: if let g = store.goal { title = g.title; notes = g.notes ?? ""; amount = display(g.target); saved = display(g.saved); date = g.deadline }
            case .expense(let old):
                fixed = startMonthly
                if let e = old {
                    title = e.title; amount = display(e.cents); date = e.date
                    category = e.category == .fixed ? .other : e.category
                    if let first = e.monthlyRates?.first,
                       let rate = e.rate(in: max(BookDate.month(Date()), first.start)) {
                        title = rate.title; amount = display(rate.cents); dueDay = rate.day
                        if let active = rate.category { category = active == .fixed ? .other : active }
                    }
                }
            }
        }
    }
    func display(_ v: Int) -> String { String(v/100) + "," + String(format: "%02d", v%100) }
    func submit() {
        guard let v = amountInCents(amount) else { warning = "Informe um valor com até duas casas decimais."; return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok: Bool
        switch mode {
        case .budget: ok = store.set("budget", .budget(v))
        case .expense(let old):
            guard !name.isEmpty, v > 0 else { warning = "Preencha a descrição e um valor maior que zero."; return }
            if let source = old, source.repeatsMonthly {
                ok = store.updateMonthly(source, title: name, cents: v, day: dueDay, category: category)
            } else {
                let markedEssential = old?.fixed ?? false
                var e = Expense(id: old?.id ?? UUID(), title: name, cents: v, category: category,
                                date: date, fixed: fixed || markedEssential, civilDay: BookDate.stamp(date))
                if fixed {
                    e.revise(MonthlyRate(category: category, start: BookDate.month(date), title: name, cents: v,
                                         day: BookDate.cal.component(.day, from: date)))
                }
                ok = store.set(e.id.uuidString, .expense(e))
            }
        case .goal:
            guard !name.isEmpty, v > 0, let savedValue = amountInCents(saved) else { warning = "Confira o nome, o valor da meta e a quantia guardada."; return }
            let description = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            ok = store.set("goal", .goal(Goal(title: name, target: v, saved: savedValue, deadline: date,
                                               notes: description.isEmpty ? nil : description)))
        }
        if ok { dismiss() } else { warning = "A alteração não foi salva." }
    }
}

struct LedgerDateField: View {
    @Binding var date: Date
    @Binding var dueDay: Int
    let monthlyDay: Bool
    var label = "Dia"
    @State private var show = false
    @State private var browsing = Date()
    var body: some View {
        LabeledContent(monthlyDay ? "Dia de cada mês" : label) {
            Button {
                browsing = date
                show = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: monthlyDay ? "repeat" : "calendar").foregroundStyle(Color.mintLeaf)
                    if monthlyDay { Text("Dia " + String(dueDay)) }
                    else { Text(date, format: .dateTime.day().month(.abbreviated).year()) }
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 3)
            }
            .buttonStyle(FinanceButtonStyle())
            .popover(isPresented: $show) {
                VStack(alignment: .leading, spacing: 14) {
                    if monthlyDay {
                        Text("Dia da cobrança").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                            ForEach(1...31, id: \.self) { day in
                                DayChip(day: day, selected: day == dueDay) { dueDay = day; show = false }
                            }
                        }
                        Divider()
                        Text("Em meses mais curtos, a cobrança cai no último dia.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        MonthGrid(monthDate: $browsing, selected: date) { day in date = day; show = false }
                    }
                }
                .padding(18).frame(width: 322)
                .background(LinearGradient(colors: [Color.pine.opacity(0.55), Color.carbon], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
    }
}

func amountInCents(_ input: String) -> Int? {
    let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let s = raw.contains(",") ? raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : raw
    guard s.range(of: #"^[0-9]{1,9}(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil else { return nil }
    let parts = s.components(separatedBy: ".")
    let fraction = parts.count > 1 ? parts[1] : ""
    return (Int(parts[0]) ?? 0)*100 + (Int(String((fraction+"00").prefix(2))) ?? 0)
}
