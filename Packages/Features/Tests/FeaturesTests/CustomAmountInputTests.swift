import XCTest
import SwiftData
import Core
import Persistence
import Notifications
@testable import Features

/// Точний ввід у шторці «Інше» (WAT-50): тап по числу — цифрова клавіатура, степери й чипи лишаються.
@MainActor
final class CustomAmountInputTests: XCTestCase {
    private var services: AppServices!
    private var model: HomeViewModel!

    override func setUp() async throws {
        try await super.setUp()
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 1; parts.hour = 10
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        services = AppServices(container: Database.makeInMemoryContainer(),
                               clock: FixedClock(now: calendar.date(from: parts)!),
                               notificationCenter: InMemoryNotificationCenter())
        services.bootstrap()
        model = HomeViewModel(services: services)
        model.openCustom()
    }

    private var todayMl: Int { services.hydration.todaySnapshot().totalMl }

    func testTypingReplacesTheValueInsteadOfAppending() {
        model.beginCustomTyping()
        XCTAssertEqual(model.customFieldText, "", "поле порожнє — попереднє видно сірим підказом")
        XCTAssertEqual(model.customAmount, 300)

        model.typeCustom("314")
        XCTAssertEqual(model.customFieldText, "314")
        XCTAssertEqual(model.customAmount, 314)

        model.confirmCustom()
        XCTAssertEqual(todayMl, 314)
        XCTAssertNil(model.customTyped)
        model.openCustom()
        XCTAssertEqual(model.customAmount, 314, "наступне «Інше» — з набраним, як і з будь-яким іншим об'ємом")
    }

    /// `TextField` на початку редагування сам пише в прив'язку поточне число — ще до зміни фокуса.
    func testFieldEchoBeforeFocusIsNotTyping() {
        model.typeCustom("300")
        XCTAssertNil(model.customTyped, "інакше поле не очиститься, і «3» допишеться до «300»")
        model.beginCustomTyping()
        XCTAssertEqual(model.customFieldText, "")
    }

    func testOutOfRangeDisablesConfirmUntilTypingEnds() {
        model.beginCustomTyping()
        model.typeCustom("5")
        XCTAssertFalse(model.isCustomAmountValid, "на півдорозі до «50» — «Додати» неактивна")
        XCTAssertEqual(model.customUnitCaption, "від 50 до 2000 мл", "без розділювача тисяч")
        model.confirmCustom()
        XCTAssertEqual(todayMl, 0, "і нічого не записує")

        model.endCustomTyping()
        XCTAssertEqual(model.customAmount, 50, "сховали клавіатуру — число стає в межі")
        XCTAssertTrue(model.isCustomAmountValid)

        model.beginCustomTyping()
        model.typeCustom("3000")
        XCTAssertFalse(model.isCustomAmountValid)
        model.endCustomTyping()
        XCTAssertEqual(model.customAmount, 2000)
    }

    /// В унціях набирають унції: поле й підказ — в унціях, порція — в мілілітрах (WAT-46), межі — цілі унції
    /// всередині 50…2000 мл.
    func testTypingInOunces() {
        services.hydration.setVolumeUnit(.usFluidOunces)
        model.reload()
        model.openCustom()
        XCTAssertEqual(model.customUnitCaption, "унц.")

        model.beginCustomTyping()
        model.typeCustom("1")
        XCTAssertEqual(model.customAmount, 30)
        XCTAssertFalse(model.isCustomAmountValid, "1 унц. — менше за 50 мл")
        XCTAssertEqual(model.customUnitCaption, "від 2 до 67 унц.")
        model.typeCustom("68")
        XCTAssertFalse(model.isCustomAmountValid, "68 унц. — уже понад 2000 мл")

        model.typeCustom("12")
        XCTAssertEqual(model.customFieldText, "12")
        XCTAssertEqual(model.customAmount, 355)
        model.confirmCustom()
        XCTAssertEqual(todayMl, 355)
        model.openCustom()
        XCTAssertEqual(model.customFieldText, "12", "наступне «Інше» — ті самі 12 унц.")
    }

    func testOnlyDigitsWithoutLeadingZerosAndAtMostFour() {
        model.beginCustomTyping()
        model.typeCustom("0,33 л")
        XCTAssertEqual(model.customFieldText, "33")
        model.typeCustom("00314")
        XCTAssertEqual(model.customFieldText, "314")
        model.typeCustom("123456")
        XCTAssertEqual(model.customFieldText, "1234")
        XCTAssertEqual(model.customAmount, 1234)
    }

    func testClearedFieldKeepsThePreviousValue() {
        model.beginCustomTyping()
        model.typeCustom("31")
        model.typeCustom("")
        XCTAssertEqual(model.customAmount, 300, "стерли набране — те саме, що й не набирали")
        model.endCustomTyping()
        XCTAssertEqual(model.customFieldText, "300")
    }

    func testChipAndStepperEndTyping() {
        model.beginCustomTyping()
        model.typeCustom("31")
        model.selectCustom(250)
        XCTAssertNil(model.customTyped, "чип — готовий вибір: клавіатура ховається")
        XCTAssertEqual(model.customAmount, 250)

        model.beginCustomTyping()
        model.typeCustom("314")
        model.stepCustom(up: true)
        XCTAssertNil(model.customTyped)
        XCTAssertEqual(model.customAmount, 350, "крок — від набраного до наступного вузла сітки (`VolumeGrid`, WAT-46)")
    }

    func testReopeningDropsUnfinishedTyping() {
        model.beginCustomTyping()
        model.typeCustom("31")
        model.dismissSheet()

        model.openCustom()
        XCTAssertNil(model.customTyped)
        XCTAssertEqual(model.customAmount, 300)

        model.beginCustomTyping()
        model.typeCustom("31")
        model.apply(.customAmount(250))
        XCTAssertNil(model.customTyped, "тап по сповіщенню — з порцією P, а не з недобраним")
        XCTAssertEqual(model.customFieldText, "250")
    }
}
