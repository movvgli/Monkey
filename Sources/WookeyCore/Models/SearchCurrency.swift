import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum SearchCurrency: String, CaseIterable, Identifiable, Sendable {
    case usd = "USD", jpy = "JPY", krw = "KRW", eur = "EUR"
    case gbp = "GBP", cny = "CNY", aud = "AUD", cad = "CAD"
    case chf = "CHF", hkd = "HKD", sgd = "SGD"

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .usd: "미국 달러"
        case .jpy: "일본 엔"
        case .krw: "한국 원"
        case .eur: "유로"
        case .gbp: "영국 파운드"
        case .cny: "중국 위안"
        case .aud: "호주 달러"
        case .cad: "캐나다 달러"
        case .chf: "스위스 프랑"
        case .hkd: "홍콩 달러"
        case .sgd: "싱가포르 달러"
        }
    }

    fileprivate var aliases: [String] {
        switch self {
        case .usd: ["미국 달러", "미국달러", "미 달러", "미달러", "달러화", "달러", "us dollars", "us dollar", "u.s. dollars", "u.s. dollar", "dollars", "dollar", "$"]
        case .jpy: ["일본 엔화", "일본엔화", "일본 엔", "일본엔", "엔화", "엔", "japanese yen", "yen", "¥"]
        case .krw: ["대한민국 원", "한국 원화", "한국원화", "한국 원", "한국원", "원화", "원", "south korean won", "korean won", "won", "₩"]
        case .eur: ["유로화", "유로", "euros", "euro", "€"]
        case .gbp: ["영국 파운드", "영국파운드", "파운드", "british pounds", "british pound", "pounds sterling", "pound sterling", "pounds", "pound", "£"]
        case .cny: ["중국 위안화", "중국위안화", "중국 위안", "중국위안", "위안화", "위안", "중국돈", "chinese yuan", "renminbi", "yuan", "rmb"]
        case .aud: ["호주 달러", "호주달러", "australian dollars", "australian dollar", "a$"]
        case .cad: ["캐나다 달러", "캐나다달러", "canadian dollars", "canadian dollar", "c$"]
        case .chf: ["스위스 프랑", "스위스프랑", "swiss francs", "swiss franc"]
        case .hkd: ["홍콩 달러", "홍콩달러", "hong kong dollars", "hong kong dollar", "hk$"]
        case .sgd: ["싱가포르 달러", "싱가포르달러", "singapore dollars", "singapore dollar", "s$"]
        }
    }

    public func formattedAmount(_ amount: Decimal) -> String {
        let wholeCurrency = self == .krw || self == .jpy
        let digits = wholeCurrency && (amount == 0 || abs(amount) >= 1) ? 0 : 2
        return SearchNumber.formatted(amount, maximumFractionDigits: digits)
    }
}

public struct SearchCurrencyQuery: Equatable, Sendable {
    public let amount: Decimal
    public let base: SearchCurrency
    public let target: SearchCurrency?

    public var targets: [SearchCurrency] {
        if let target { return [target] }
        return [.krw, .usd, .jpy, .eur].filter { $0 != base }
    }

    private static let aliases = SearchCurrency.allCases.flatMap { currency in
        ([currency.rawValue.lowercased()] + currency.aliases).map { (text: $0, currency: currency) }
    }.sorted { $0.text.count > $1.text.count }
    private static let amountPattern = try! NSRegularExpression(pattern: "^[+-]?(?:[0-9][0-9,]*(?:\\.[0-9]*)?|\\.[0-9]+)")

    public static func parse(_ input: String) -> Self? {
        guard input.count <= 160 else { return nil }
        var scanner = Scanner(text: SearchNumber.normalized(input).split(whereSeparator: \.isWhitespace).joined(separator: " "))
        if ["환율", "exchange rate", "exchange rates"].contains(scanner.text) {
            return Self(amount: 1, base: .usd, target: nil)
        }
        _ = scanner.consume(any: ["convert", "환율"])
        let amountFirst = scanner.takeAmount()
        guard let base = scanner.takeCurrency() else { return nil }
        let amount = amountFirst ?? scanner.takeAmount() ?? 1
        _ = scanner.consume(any: ["에서", "를", "을", "는", "은"])
        let hasSeparator = scanner.consume(any: ["으로", "로", "->", "→", "/", "into", "to", "in"])
        let target = scanner.takeCurrency()
        if hasSeparator && target == nil { return nil }
        if target != nil { _ = scanner.consume(any: ["으로", "로"]) }
        _ = scanner.consume(any: ["exchange rates", "exchange rate", "환율"])
        _ = scanner.consume(any: ["얼마인가요", "얼마예요", "얼마야", "얼마", "how much"])
        _ = scanner.consume(any: ["?"])
        guard scanner.text.isEmpty else { return nil }
        return Self(amount: amount, base: base, target: target)
    }

    private struct Scanner {
        var text: String

        mutating func takeCurrency() -> SearchCurrency? {
            for alias in SearchCurrencyQuery.aliases where consume(alias.text) { return alias.currency }
            return nil
        }

        mutating func takeAmount() -> Decimal? {
            guard let match = SearchCurrencyQuery.amountPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range, in: text),
                  let value = SearchNumber.decimal(String(text[range])) else { return nil }
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return value
        }

        mutating func consume(any values: [String]) -> Bool {
            for value in values where consume(value) { return true }
            return false
        }

        private mutating func consume(_ value: String) -> Bool {
            guard text.hasPrefix(value) else { return false }
            let remaining = text.dropFirst(value.count)
            if let last = value.last, let next = remaining.first,
               last.isASCII && last.isLetter && next.isASCII && next.isLetter { return false }
            text = remaining.trimmingCharacters(in: .whitespaces)
            return true
        }
    }
}

public struct SearchExchangeRateTable: Sendable {
    public let date: String
    private let unitsPerEuro: [SearchCurrency: Decimal]

    public func rate(from base: SearchCurrency, to target: SearchCurrency) -> Decimal? {
        guard let source = unitsPerEuro[base], let destination = unitsPerEuro[target] else { return nil }
        return destination / source
    }

    static func parse(_ data: Data) throws -> Self {
        let delegate = ECBParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let date = delegate.date,
              date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              [SearchCurrency.usd, .jpy, .krw].allSatisfy({ delegate.rates[$0] != nil }) else {
            throw URLError(.cannotParseResponse)
        }
        return Self(date: date, unitsPerEuro: delegate.rates)
    }

    private final class ECBParser: NSObject, XMLParserDelegate {
        var date: String?
        var rates: [SearchCurrency: Decimal] = [.eur: 1]

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String]
        ) {
            guard elementName == "Cube" else { return }
            if let time = attributeDict["time"] { date = time }
            if let currency = attributeDict["currency"].flatMap(SearchCurrency.init(rawValue:)), currency != .eur,
               let rate = attributeDict["rate"].flatMap(SearchNumber.decimal), rate > 0 {
                rates[currency] = rate
            }
        }
    }
}

public actor SearchExchangeRates {
    public static let shared = SearchExchangeRates()

    public struct Snapshot: Sendable {
        public let rates: SearchExchangeRateTable
        public let usedFallback: Bool
    }

    private var cached: (rates: SearchExchangeRateTable, fetchedAt: Date)?

    public func latest() async throws -> Snapshot {
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < 30 * 60 {
            return Snapshot(rates: cached.rates, usedFallback: false)
        }
        // The fixed ECB feed URL keeps the user's amount and search text on the Mac.
        let url = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let rates = try SearchExchangeRateTable.parse(data)
            cached = (rates, Date())
            return Snapshot(rates: rates, usedFallback: false)
        } catch {
            try Task.checkCancellation()
            if let cached { return Snapshot(rates: cached.rates, usedFallback: true) }
            throw error
        }
    }
}
