import Foundation

enum Category: String, Codable, CaseIterable, Identifiable {
    case food = "Comida", subscription = "Assinaturas", housing = "Moradia", transport = "Transporte", leisure = "Lazer", fixed = "Gastos fixos", other = "Outros"
    var id: Self { self }
    var label: String { self == .other || self == .fixed ? "Outro" : rawValue }
    static var selectable: [Self] { allCases.filter { $0 != .fixed } }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .other
    }
    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .subscription: return "repeat"
        case .housing: return "house"
        case .transport: return "tram"
        case .leisure: return "ticket"
        case .fixed: return "pin"
        case .other: return "circle.grid.2x2"
        }
    }
}
struct Expense: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var cents: Int
    var category: Category
    var date: Date
    var fixed: Bool
    // Optional fields keep ledgers from 1.1 readable, including essential one-off expenses.
    var civilDay: Int?
    var monthlyRates: [MonthlyRate]?
    var endsBefore: Int?

    var repeatsMonthly: Bool { monthlyRates?.isEmpty == false }
    var occurrenceKey: String { id.uuidString + "-" + String(BookDate.month(date)) }

    func occurrence(in month: Int) -> Expense? {
        var item = self
        if item.category == .fixed { item.category = .other }
        guard repeatsMonthly else {
            if let day = civilDay { item.date = BookDate.date(in: day / 100, day: day % 100) }
            return BookDate.month(item.date) == month ? item : nil
        }
        if let end = endsBefore, month >= end { return nil }
        guard let rate = rate(in: month) else { return nil }
        item.title = rate.title
        item.cents = rate.cents
        if let category = rate.category { item.category = category == .fixed ? .other : category }
        item.date = BookDate.date(in: month, day: rate.day)
        item.fixed = true
        return item
    }

    func rate(in month: Int) -> MonthlyRate? {
        monthlyRates?.last(where: { $0.start <= month })
    }

    mutating func revise(_ rate: MonthlyRate) {
        var history = monthlyRates ?? []
        history.removeAll { $0.start == rate.start }
        history.append(rate)
        monthlyRates = history.sorted { $0.start < $1.start }
    }
}

extension Expense {
    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        id = try data.decode(UUID.self, forKey: .id)
        title = try data.decode(String.self, forKey: .title)
        cents = try data.decode(Int.self, forKey: .cents)
        category = try data.decodeIfPresent(Category.self, forKey: .category) ?? .other
        date = try data.decode(Date.self, forKey: .date)
        fixed = try data.decode(Bool.self, forKey: .fixed)
        civilDay = try data.decodeIfPresent(Int.self, forKey: .civilDay)
        monthlyRates = try data.decodeIfPresent([MonthlyRate].self, forKey: .monthlyRates)
        endsBefore = try data.decodeIfPresent(Int.self, forKey: .endsBefore)
    }
}

struct MonthlyRate: Codable, Equatable {
    var category: Category? = nil
    let start: Int  // inclusive YYYYMM
    let title: String
    let cents: Int
    let day: Int    // desired day, including 29–31 in a shorter month
}

enum BookDate {
    static var cal: Calendar { Calendar(identifier: .gregorian) }
    static func month(_ date: Date) -> Int {
        cal.component(.year, from: date) * 100 + cal.component(.month, from: date)
    }
    static func stamp(_ date: Date) -> Int {
        month(date) * 100 + cal.component(.day, from: date)
    }
    static func date(in month: Int, day: Int) -> Date {
        let first = cal.date(from: DateComponents(year: month / 100, month: month % 100, day: 1, hour: 12))!
        let count = cal.range(of: .day, in: .month, for: first)!.count
        return cal.date(byAdding: .day, value: min(max(day, 1), count) - 1, to: first)!
    }
    static func shift(_ date: Date, by months: Int) -> Date {
        let first = self.date(in: month(date), day: 1)
        return cal.date(byAdding: .month, value: months, to: first)!
    }
}

struct Goal: Codable, Equatable {
    var title: String
    var target: Int
    var saved: Int
    var deadline: Date
    var notes: String? = nil
}
enum Content: Codable, Equatable {
    case expense(Expense), goal(Goal), budget(Int), deleted
}
struct Entry: Codable, Equatable {
    var clock: Int
    var device: String
    var value: Content
}
typealias Ledger = [String: Entry]
func money(_ cents: Int) -> String {
    let reais: Double = Double(cents) / 100.0
    let style = FloatingPointFormatStyle<Double>.Currency(code: "BRL", locale: Locale(identifier: "pt_BR"))
    return reais.formatted(style)
}
func sameMonth(_ a: Date, _ b: Date) -> Bool {
    Calendar.current.isDate(a, equalTo: b, toGranularity: .month)
}
struct Plan {
    var remaining: Int, months: Int, average: Int, now: Int, future: Int, shortage: Int
    var cuts: [(Category, Int)]
    var expired: Bool
    init(goal: Goal, budget: Int, expenses: [Expense], today: Date = Date()) {
        let cal = Calendar.current
        let startMonth = cal.dateInterval(of: .month, for: today)!.start
        let endMonth = cal.dateInterval(of: .month, for: goal.deadline)!.start
        let difference = cal.dateComponents([.month], from: startMonth, to: endMonth)
        let monthCount: Int = max(1, (difference.month ?? 0) + 1)
        months = monthCount
        expired = cal.startOfDay(for: goal.deadline) < cal.startOfDay(for: today)
        remaining = max(0, goal.target - goal.saved)
        average = (remaining + monthCount - 1) / monthCount

        var spent = 0
        var adjustableTotal = 0
        var adjustableByCategory: [Category: Int] = [:]
        for expense in expenses where sameMonth(expense.date, today) {
            spent += expense.cents
            if !expense.fixed && expense.category != .fixed {
                adjustableByCategory[expense.category, default: 0] += expense.cents
                adjustableTotal += expense.cents
            }
        }

        let free: Int = budget - spent
        now = min(max(0, free), average)
        future = 0
        if monthCount > 1 {
            let laterMonths = monthCount - 1
            let laterAmount = remaining - now
            future = (laterAmount + laterMonths - 1) / laterMonths
        }

        let gap: Int = max(0, future - free)
        cuts = []
        if monthCount == 1 {
            shortage = remaining - now
            return
        }
        shortage = max(0, gap - adjustableTotal)
        var toCut: Int = min(gap, adjustableTotal)
        var base: Int = adjustableTotal
        let ranked: [Dictionary<Category, Int>.Element] = adjustableByCategory.sorted { first, second in
            if first.value == second.value {
                return first.key.rawValue < second.key.rawValue
            }
            return first.value > second.value
        }

        for item in ranked where base > 0 {
            let amount: Int = item.value
            let weightedAmount: Double = Double(toCut) * Double(amount)
            let share: Double = weightedAmount / Double(base)
            let part: Int = min(amount, Int(share.rounded()))
            if part > 0 { cuts.append((item.key, part)) }
            toCut -= part
            base -= amount
        }
    }
}
