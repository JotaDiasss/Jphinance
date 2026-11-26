import Foundation
import SwiftUI
import CryptoKit
import Security

enum StoreError: Error { case invalid, denied, conflict, storage }
struct Blob: Codable { let iv: Data; let data: Data }
struct RequestBody: Encodable { let token: String; let op: String; var rev: Int?; var blob: Blob? }
struct Reply: Decodable { let rev: Int?; let blob: Blob?; let conflict: Bool? }
enum KeyStore {
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Jphinance.Sync.v1", kSecAttrAccount as String: "personal"]
    }
    static func read() -> Data? {
        var q = query; q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
    static func save(_ data: Data) throws {
        let fields: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(fields) { _, v in v } as CFDictionary, nil) == errSecSuccess else { throw StoreError.storage }
        } else if status != errSecSuccess { throw StoreError.storage }
    }
}
@MainActor final class Store: ObservableObject {
    @Published private(set) var rows: Ledger = [:]
    @Published var status = "Somente neste aparelho"
    @Published var message: String?
    @Published private(set) var connected = false
    private let file: URL
    private let device = UUID().uuidString
    private var key: Data?
    private var syncing = false
    private var pending = false
    private var failedLoad = false
    private static let host = Bundle.main.object(forInfoDictionaryKey: "JphinanceSyncHost") as? String ?? ""
    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jphinance", isDirectory: true).appendingPathComponent("ledger.json")
        key = KeyStore.read()
        connected = key != nil
        if FileManager.default.fileExists(atPath: file.path) {
            do { rows = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file)) }
            catch { failedLoad = true; message = "Não foi possível abrir os dados salvos." }
        }
        if connected { status = "Aguardando sincronização" }
    }
    private var expenses: [Expense] {
        rows.values.compactMap { entry in
            guard case .expense(let item) = entry.value else { return nil }
            return item
        }
    }
    func entries(in date: Date) -> [Expense] {
        let month = BookDate.month(date)
        return expenses.compactMap { $0.occurrence(in: month) }.sorted(by: Self.displayOrder)
    }
    private static func displayOrder(_ a: Expense, _ b: Expense) -> Bool {
        let first = BookDate.stamp(a.date), second = BookDate.stamp(b.date)
        if first != second { return first > second }
        if a.title != b.title { return a.title < b.title }
        return a.id.uuidString < b.id.uuidString
    }
    var activeMonthly: [Expense] {
        let now = BookDate.month(Date())
        return expenses.compactMap { root -> Expense? in
            guard let start = root.monthlyRates?.first?.start else { return nil }
            return root.occurrence(in: max(now, start))
        }.sorted { a, b in
            let da = BookDate.cal.component(.day, from: a.date)
            let db = BookDate.cal.component(.day, from: b.date)
            return da == db ? a.title < b.title : da < db
        }
    }
    var latestEntries: [Expense] {
        let today = Date()
        let current = BookDate.month(today)
        var recent: [Expense] = []
        for root in expenses {
            if !root.repeatsMonthly {
                let month = root.civilDay.map { $0 / 100 } ?? BookDate.month(root.date)
                if let item = root.occurrence(in: month) { recent.append(item) }
                continue
            }
            let last = min(current, root.endsBefore ?? current)
            let boundary = BookDate.date(in: last, day: 1)
            for offset in 0...4 {
                let month = BookDate.month(BookDate.shift(boundary, by: -offset))
                if let item = root.occurrence(in: month), BookDate.stamp(item.date) <= BookDate.stamp(today) {
                    recent.append(item)
                }
            }
        }
        return Array(recent.sorted(by: Self.displayOrder).prefix(4))
    }
    @discardableResult func removeExpense(_ item: Expense) -> Bool {
        guard case .expense(var source)? = rows[item.id.uuidString]?.value else { return false }
        if source.repeatsMonthly {
            source.endsBefore = min(source.endsBefore ?? Int.max, BookDate.month(Date()))
            return set(item.id.uuidString, .expense(source))
        }
        return set(item.id.uuidString, .deleted)
    }
    func updateMonthly(_ item: Expense, title: String, cents: Int, day: Int, category: Category) -> Bool {
        guard case .expense(var source)? = rows[item.id.uuidString]?.value,
              let first = source.monthlyRates?.first, source.endsBefore == nil else { return false }
        let month = max(first.start, BookDate.month(Date()))
        source.revise(MonthlyRate(category: category, start: month, title: title, cents: cents, day: day))
        return set(source.id.uuidString, .expense(source))
    }
    var budget: Int { if case let .budget(v)? = rows["budget"]?.value { return v }; return 0 }
    var goal: Goal? { if case let .goal(v)? = rows["goal"]?.value { return v }; return nil }
    private func persist(_ next: Ledger) throws {
        guard !failedLoad else { throw StoreError.storage }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(next)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        rows = next
    }
    @discardableResult func set(_ id: String, _ value: Content) -> Bool {
        var next = rows
        next[id] = Entry(clock: (rows.values.map { $0.clock }.max() ?? 0) + 1, device: device, value: value)
        do { try persist(next); Task { await sync() }; return true }
        catch { message = "Não foi possível salvar a alteração neste aparelho."; return false }
    }
    static func derive(_ data: Data, _ purpose: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: data), salt: Data("Jphinance 1".utf8), info: Data(purpose.utf8), outputByteCount: 32)
    }
    private func request(_ op: String, _ secret: Data, rev: Int? = nil, blob: Blob? = nil) async throws -> Reply {
        var req = URLRequest(url: URL(string: "https://" + Self.host + "/sync")!)
        req.httpMethod = "POST"; req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = Self.derive(secret, "login").withUnsafeBytes { Data($0).base64EncodedString() }
        req.httpBody = try JSONEncoder().encode(RequestBody(token: token, op: op, rev: rev, blob: blob))
        let (data, raw) = try await URLSession.shared.data(for: req)
        guard let response = raw as? HTTPURLResponse else { throw StoreError.invalid }
        if response.statusCode == 403 { throw StoreError.denied }
        guard response.statusCode == 200 else { throw StoreError.invalid }
        return try JSONDecoder().decode(Reply.self, from: data)
    }
    func pair(_ text: String) async -> Bool {
        guard let u = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), u.host == Self.host, u.scheme == "https", u.path == "/parear", let f = u.fragment, f.count == 43,
              let data = Data(base64Encoded: f.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="), data.count == 32 else {
            message = "Cole o link privado completo do Jphinance."; return false
        }
        do {
            let reply = try await request("get", data)
            guard reply.rev != nil else { throw StoreError.invalid }
            try KeyStore.save(data); key = data; connected = true; await sync(); return true
        } catch { message = "Não foi possível conectar. Confira o link e a internet."; return false }
    }
    func sync() async {
        guard let key, !failedLoad else { return }
        if syncing { pending = true; return }
        syncing = true; defer { syncing = false }
        status = "Sincronizando…"
        do {
            repeat {
                pending = false
                let remote = try await request("get", key)
                guard let rev = remote.rev else { throw StoreError.invalid }
                let aes = Self.derive(key, "vault")
                var other: Ledger = [:]
                if let b = remote.blob {
                    guard b.data.count >= 16 else { throw StoreError.invalid }
                    let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: b.iv), ciphertext: b.data.dropLast(16), tag: b.data.suffix(16))
                    other = try JSONDecoder().decode(Ledger.self, from: AES.GCM.open(box, using: aes))
                }
                let combined = rows.merging(other) { a, b in
                    a.clock == b.clock ? (a.device >= b.device ? a : b) : (a.clock > b.clock ? a : b)
                }
                if combined != rows { try persist(combined) }
                if combined != other {
                    let sealed = try AES.GCM.seal(JSONEncoder().encode(combined), using: aes)
                    let packet = Blob(iv: sealed.nonce.withUnsafeBytes { Data($0) }, data: sealed.ciphertext + sealed.tag)
                    let result = try await request("put", key, rev: rev, blob: packet)
                    if result.conflict == true { pending = true }
                    else if result.rev != rev + 1 { throw StoreError.invalid }
                }
            } while pending && !Task.isCancelled
            status = "Sincronizado"
        } catch { status = "Salvo localmente · sincronização pendente" }
    }
}
