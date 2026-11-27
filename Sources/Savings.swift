import SwiftUI

// Existing clients preserve integer ledger entries; only the exact key "budget" is the monthly budget.
// Each deposit has its own key so concurrent deposits merge independently.
struct SavingsDeposit: Identifiable {
    let id: String
    let box: String
    let day: Int
    let cents: Int

    static func key(box: String, date: Date) -> String {
        let name = Data(box.precomposedStringWithCanonicalMapping.utf8).base64EncodedString()
        return "savings.v1:\(UUID().uuidString):\(BookDate.stamp(date)):\(name)"
    }

    init?(key: String, entry: Entry) {
        guard key.hasPrefix("savings.v1:"), case .budget(let amount) = entry.value, amount > 0 else { return nil }
        let parts = key.split(separator: ":")
        guard parts.count == 4, UUID(uuidString: String(parts[1])) != nil,
              let day = Int(parts[2]), (1...12).contains(day / 100 % 100), (1...31).contains(day % 100),
              let bytes = Data(base64Encoded: String(parts[3])), let name = String(data: bytes, encoding: .utf8),
              !name.isEmpty else { return nil }
        self.id = key; self.box = name; self.day = day; self.cents = amount
    }
}

private struct SavingsBalances {
    let groups: [String: [SavingsDeposit]]
    let names: [String]
    let total: Int

    init(rows: Ledger) {
        let deposits = rows.compactMap { SavingsDeposit(key: $0.key, entry: $0.value) }.sorted {
            $0.day == $1.day ? $0.id < $1.id : $0.day > $1.day
        }
        let grouped = Dictionary(grouping: deposits, by: \.box)
        groups = grouped
        names = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        total = deposits.reduce(0) { $0 + $1.cents }
    }
}

struct SavingsSummary: View {
    let open: () -> Void
    @EnvironmentObject private var store: Store
    var body: some View {
        let balances = SavingsBalances(rows: store.rows)
        return Panel {
            Label("Caixinhas", systemImage: "archivebox").font(.headline).foregroundStyle(Color.mintLeaf)
            VStack(alignment: .leading, spacing: 3) {
                Text("Total guardado").font(.caption).foregroundStyle(.secondary)
                Text(money(balances.total)).font(.title2.bold().monospacedDigit())
            }
            ForEach(balances.names.prefix(3), id: \.self) { name in
                HStack {
                    Text(name).lineLimit(2)
                    Spacer()
                    Text(money(balances.groups[name, default: []].reduce(0) { $0 + $1.cents })).monospacedDigit()
                }
            }
            Button("Abrir caixinhas", action: open)
        }
    }
}

private struct DepositForm: Identifiable {
    let id = UUID()
    let box: String
}

struct SavingsPage: View {
    @EnvironmentObject private var store: Store
    @State private var form: DepositForm?
    @State private var expanded: Set<String> = []
    @State private var pendingDelete: SavingsDeposit?

    var body: some View {
        let balances = SavingsBalances(rows: store.rows)
        let groups = balances.groups
        let names = balances.names
        return VStack(alignment: .leading, spacing: 18) {
            Panel {
                Label("Total guardado", systemImage: "archivebox.fill").foregroundStyle(Color.mintLeaf)
                Text(money(balances.total)).font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                Button { form = DepositForm(box: "") } label: { Label("Guardar dinheiro", systemImage: "plus") }
                    .buttonStyle(FinanceButtonStyle(appearance: .primary))
            }
            if names.isEmpty {
                Text("Registre um valor para começar sua primeira caixinha.").foregroundStyle(.secondary)
            }
            ForEach(names, id: \.self) { name in
                boxCard(name, items: groups[name] ?? [])
            }
        }
        .sheet(item: $form) { initial in
            SavingsEditor(initialBox: initial.box, names: names).environmentObject(store)
        }
        .confirmationDialog("Excluir este registro?", isPresented: Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible, presenting: pendingDelete) { item in
            Button("Excluir registro", role: .destructive) { store.set(item.id, .deleted) }
            Button("Cancelar", role: .cancel) {}
        } message: { item in Text(money(item.cents) + " serão removidos do saldo de " + item.box + ".") }
    }

    private func boxCard(_ name: String, items: [SavingsDeposit]) -> some View {
        Panel {
            HStack {
                Label(name, systemImage: "archivebox").font(.headline)
                Spacer()
                Text(money(items.reduce(0) { $0 + $1.cents })).font(.title3.bold().monospacedDigit())
            }
            HStack {
                Button("Guardar aqui") { form = DepositForm(box: name) }
                Button(expanded.contains(name) ? "Ocultar histórico" : "Ver histórico") {
                    if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
                }
            }
            if expanded.contains(name) {
                Divider()
                ForEach(items) { item in
                    HStack {
                        Text(BookDate.date(in: item.day / 100, day: item.day % 100), format: .dateTime.day().month(.wide).year())
                        Spacer()
                        Text(money(item.cents)).monospacedDigit()
                        Button { pendingDelete = item } label: { Image(systemName: "trash") }.accessibilityLabel("Excluir registro")
                    }
                }
            }
        }
    }
}

private struct SavingsEditor: View {
    let initialBox: String
    let names: [String]
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var box = ""
    @State private var amount = ""
    @State private var day = Date()
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Guardar dinheiro").font(.title2.bold())
            HStack {
                TextField("Nome da caixinha", text: $box)
                if !names.isEmpty {
                    Menu { ForEach(names, id: \.self) { name in Button(name) { box = name } } }
                    label: { Image(systemName: "chevron.down") }.accessibilityLabel("Escolher caixinha")
                }
            }
            TextField("Valor (R$)", text: $amount)
            LedgerDateField(date: $day, dueDay: .constant(1), monthlyDay: false)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(Color.mintLeaf) }
            HStack { Spacer(); Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar") { save() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(FinanceButtonStyle(appearance: .primary))
            }
        }
        .textFieldStyle(.roundedBorder).padding(24).frame(minWidth: 360)
        .onAppear { box = initialBox.isEmpty ? "Reserva livre" : initialBox }
    }
    private func save() {
        let text = box.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 64 else { error = "Use um nome de até 64 caracteres."; return }
        guard let value = amountInCents(amount), value > 0 else { error = "Informe um valor maior que zero."; return }
        let name = names.first { $0.caseInsensitiveCompare(text) == .orderedSame } ?? text
        if store.set(SavingsDeposit.key(box: name, date: day), .budget(value)) { dismiss() }
        else { error = "Não foi possível salvar este registro." }
    }
}
