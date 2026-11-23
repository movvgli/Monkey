import Foundation
import Testing
@testable import WookeyCore

struct SearchUtilityTests {
    @Test func webSearchPreservesSpacesAndSpecialCharacters() throws {
        let url = try #require(SearchWebAddress.searchURL(for: "  우키 C++ & Swift #1  "))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "www.google.com")
        #expect(components.path == "/search")
        #expect(components.queryItems == [URLQueryItem(name: "q", value: "우키 C++ & Swift #1")])
        #expect(components.percentEncodedQuery?.contains("C%2B%2B") == true)
        #expect(SearchWebAddress.searchURL(for: "  \n") == nil)
    }

    @Test func webAddressesSupportPastedLinksAndBareDomains() {
        let full = "http://example.com:8080/path?q=hello%20world#page"
        #expect(SearchWebAddress.parse(" \(full)\n")?.absoluteString == full)
        #expect(SearchWebAddress.parse("example.com/path?return=https://example.org")?.absoluteString
                == "https://example.com/path?return=https://example.org")
        #expect(SearchWebAddress.parse("https://한글.kr/문서")?.scheme == "https")
    }

    @Test(arguments: [
        "", "Calendar", "hello world", "달러 환율", "3.14", "3.14*2",
        "name@example.com", "example..com", "-example.com", "https://",
        "ftp://example.com", "file:///Applications", "javascript:alert(1)"
    ])
    func webAddressDetectionLeavesOrdinarySearchAndOtherSchemesAlone(_ input: String) {
        #expect(SearchWebAddress.parse(input) == nil)
    }

    @Test func arithmeticUsesGroupingAndOperatorPrecedence() {
        #expect(SearchCalculation.evaluate("100+10000") == .value(10_100))
        #expect(SearchCalculation.evaluate("100+10,000") == .value(10_100))
        #expect(SearchCalculation.evaluate("(100 + 10,000) ÷ 2") == .value(5_050))
        #expect(SearchCalculation.evaluate(" ２×（３＋４） ") == .value(14))
        #expect(SearchCalculation.evaluate("2 + 3 * -4") == .value(-10))
        #expect(SearchCalculation.evaluate("0.1 + .2") == .value(Decimal(string: "0.3")!))
    }

    @Test func arithmeticSurfacesErrorsWithoutClaimingOrdinarySearches() {
        #expect(SearchCalculation.evaluate("1/(2-2)") == .error(.divisionByZero))
        #expect(SearchCalculation.evaluate("100+10,00") == .error(.invalidExpression))
        #expect(SearchCalculation.evaluate("2 + (3") == .error(.invalidExpression))
        #expect(SearchCalculation.evaluate("100유로") == nil)
        #expect(SearchCalculation.evaluate("gcal") == nil)
        #expect(SearchCalculation.evaluate("10000") == nil)
        #expect(SearchNumber.formatted(10_100) == "10,100")
    }

    @Test func amountAndCurrencyNamesWorkInBothLanguages() throws {
        let euro = try #require(SearchCurrencyQuery.parse("100유로"))
        #expect(euro.base == .eur)
        #expect(euro.amount == 100)
        #expect(euro.targets == [.krw, .usd, .jpy])
        #expect(SearchCurrencyQuery.parse("100 EUR") == euro)
        #expect(SearchCurrencyQuery.parse("EUR 100") == euro)
        #expect(SearchCurrencyQuery.parse("€100") == euro)

        let dollar = try #require(SearchCurrencyQuery.parse("1,000.25 US dollars to 원화"))
        #expect(dollar.base == .usd)
        #expect(dollar.amount == Decimal(string: "1000.25"))
        #expect(dollar.targets == [.krw])
        #expect(SearchCurrencyQuery.parse("1,000.25달러를 원화로 얼마") == dollar)
        #expect(SearchCurrencyQuery.parse("100 Japanese yen to euros")?.targets == [.eur])
        #expect(SearchCurrencyQuery.parse("달러 환율")?.amount == 1)
        #expect(SearchCurrencyQuery.parse("USD/KRW")?.targets == [.krw])
        #expect(SearchCurrencyQuery.parse("100영국 파운드 원화")?.base == .gbp)
    }

    @Test func malformedAmountsAndUnknownTargetsAreRejected() {
        #expect(SearchCurrencyQuery.parse("100USD to") == nil)
        #expect(SearchCurrencyQuery.parse("100USD to BTC") == nil)
        #expect(SearchCurrencyQuery.parse("1,00유로") == nil)
        #expect(SearchCurrencyQuery.parse("100 dollars blog") == nil)
        #expect(SearchCurrencyQuery.parse("eurovision") == nil)
        #expect(SearchCurrencyQuery.parse("원본 문서") == nil)
    }

    @Test func officialRatesProduceSameDayCrossRates() throws {
        let sample = """
            <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
              <Cube><Cube time="2026-11-20">
                <Cube currency="USD" rate="1.25"/><Cube currency="JPY" rate="175.5"/>
                <Cube currency="KRW" rate="1500"/><Cube currency="CHF" rate="0"/>
              </Cube></Cube>
            </gesmes:Envelope>
            """
        let table = try SearchExchangeRateTable.parse(Data(sample.utf8))
        #expect(table.date == "2026-11-20")
        #expect(table.rate(from: .eur, to: .usd) == Decimal(string: "1.25"))
        #expect(table.rate(from: .usd, to: .krw) == 1_200)
        #expect(table.rate(from: .usd, to: .eur) == Decimal(string: "0.8"))
        #expect(table.rate(from: .eur, to: .chf) == nil)
        #expect(throws: URLError.self) { try SearchExchangeRateTable.parse(Data("<Cube/>".utf8)) }
    }
}
