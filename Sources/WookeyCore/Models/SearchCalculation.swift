import Foundation

public enum SearchNumber {
    private static let inputLocale = Locale(identifier: "en_US_POSIX")

    public static func decimal(_ text: String) -> Decimal? {
        let sign = text.first == "-" ? "-" : ""
        let unsigned = text.first == "-" || text.first == "+" ? String(text.dropFirst()) : text
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard let integer = parts.first, parts.count <= 2 else { return nil }
        let fraction = parts.count == 2 ? parts[1] : ""
        let groups = integer.split(separator: ",", omittingEmptySubsequences: false)
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        let digits = groups.joined()
        guard (1...34).contains(digits.count + fraction.count),
              digits.allSatisfy(isDigit), fraction.allSatisfy(isDigit) else { return nil }
        let magnitude = (digits.isEmpty ? "0" : digits) + (fraction.isEmpty ? "" : ".\(fraction)")
        return Decimal(string: sign + magnitude, locale: inputLocale)
    }

    public static func formatted(_ value: Decimal, maximumFractionDigits: Int = 10) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfUp
        let number = NSDecimalNumber(decimal: value)
        guard let formatted = formatter.string(from: number) else { return number.stringValue }
        return value != 0 && (formatted == "0" || formatted == "-0") ? number.stringValue : formatted
    }

    static func isDigit(_ character: Character) -> Bool { ("0"..."9").contains(character) }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.widthInsensitive, .caseInsensitive], locale: inputLocale)
            .replacingOccurrences(of: "−", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum SearchCalculation: Equatable {
    case value(Decimal)
    case error(Failure)

    public enum Failure: LocalizedError, Equatable {
        case invalidExpression
        case divisionByZero
        case outOfRange

        public var errorDescription: String? {
            switch self {
            case .invalidExpression: L10n.text("계산식을 확인해 주세요.")
            case .divisionByZero: L10n.text("0으로 나눌 수 없습니다.")
            case .outOfRange: L10n.text("계산할 수 있는 숫자 범위를 벗어났습니다.")
            }
        }
    }

    public static func evaluate(_ query: String) -> Self? {
        var expression = SearchNumber.normalized(query)
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
        let explicit = expression.hasPrefix("=") || expression.hasSuffix("=")
        if expression.hasPrefix("=") { expression.removeFirst() }
        if expression.hasSuffix("=") { expression.removeLast() }
        guard expression.contains(where: SearchNumber.isDigit),
              explicit || expression.contains(where: { "+-*/()".contains($0) }),
              expression.allSatisfy({ SearchNumber.isDigit($0) || $0.isWhitespace || "+-*/().,".contains($0) }) else { return nil }
        guard expression.count <= 160 else { return .error(.outOfRange) }

        var parser = Parser(characters: Array(expression))
        do { return .value(try parser.parse()) }
        catch let failure as Failure { return .error(failure) }
        catch { return .error(.invalidExpression) }
    }

    private struct Parser {
        var characters: [Character]
        var index = 0

        mutating func parse() throws -> Decimal {
            let value = try sum()
            skipWhitespace()
            guard index == characters.count else { throw Failure.invalidExpression }
            return value
        }

        private mutating func sum() throws -> Decimal {
            var value = try product()
            while true {
                if consume("+") { value = try calculate(value, product(), using: NSDecimalAdd) }
                else if consume("-") { value = try calculate(value, product(), using: NSDecimalSubtract) }
                else { return value }
            }
        }

        private mutating func product() throws -> Decimal {
            var value = try factor()
            while true {
                if consume("*") { value = try calculate(value, factor(), using: NSDecimalMultiply) }
                else if consume("/") { value = try calculate(value, factor(), using: NSDecimalDivide) }
                else { return value }
            }
        }

        private mutating func factor() throws -> Decimal {
            if consume("+") { return try factor() }
            if consume("-") { return try -factor() }
            if consume("(") {
                let value = try sum()
                guard consume(")") else { throw Failure.invalidExpression }
                return value
            }

            let start = index
            while index < characters.count,
                  SearchNumber.isDigit(characters[index]) || ".,".contains(characters[index]) {
                index += 1
            }
            guard let value = SearchNumber.decimal(String(characters[start..<index])) else { throw Failure.invalidExpression }
            return value
        }

        private mutating func consume(_ character: Character) -> Bool {
            skipWhitespace()
            guard index < characters.count, characters[index] == character else { return false }
            index += 1
            return true
        }

        private mutating func skipWhitespace() {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
        }

        private func calculate(
            _ left: Decimal,
            _ right: Decimal,
            using operation: (UnsafeMutablePointer<Decimal>, UnsafePointer<Decimal>, UnsafePointer<Decimal>, Decimal.RoundingMode) -> Decimal.CalculationError
        ) throws -> Decimal {
            var left = left
            var right = right
            var value = Decimal()
            switch operation(&value, &left, &right, .plain) {
            case .noError, .lossOfPrecision: return value
            case .divideByZero: throw Failure.divisionByZero
            default: throw Failure.outOfRange
            }
        }
    }
}
