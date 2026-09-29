import Testing
import Foundation
#if canImport(HomeKit)
import HomeKit
#endif
@testable import AppleToolbox

struct HomeInspectorFormatTests {
    private func characteristic(
        format: HomeCharacteristicFormat?, properties: [HomeCharacteristicProperty] = [.readable, .writable],
        minimum: Double? = nil, maximum: Double? = nil, step: Double? = nil, validValues: [Int] = [],
        units: String? = nil, names: [HomeValueChoice] = [], value: HomeCharacteristicValue? = nil
    ) -> HomeCharacteristicInfo {
        HomeCharacteristicInfo(
            id: UUID(), name: "Test", type: "00000000-0000-1000-8000-0026BB765291", properties: properties,
            format: format, rawFormat: format?.rawValue, units: units, minimum: minimum, maximum: maximum, step: step,
            maxLength: nil, validValues: validValues, manufacturerDescription: nil, value: value, namedValues: names,
            needsConfirmation: false, isNotificationEnabled: false)
    }

    @Test func readsValuesAccordingToTheFormat() {
        #expect(HomeCharacteristicValue(NSNumber(value: 1), format: .bool) == .bool(true))
        #expect(HomeCharacteristicValue(NSNumber(value: 42), format: .uint8) == .integer(42))
        #expect(HomeCharacteristicValue(NSNumber(value: 21.5), format: .float) == .number(21.5))
        #expect(HomeCharacteristicValue(NSNumber(value: true), format: nil) == .bool(true))
        #expect(HomeCharacteristicValue(NSNumber(value: 2.5), format: nil) == .number(2.5))
        #expect(HomeCharacteristicValue(NSNumber(value: 7), format: nil) == .integer(7))
        #expect(HomeCharacteristicValue("Hall", format: .string) == .text("Hall"))
        #expect(HomeCharacteristicValue(Data([1, 2, 3]), format: .tlv8) == .bytes(3))
        #expect(HomeCharacteristicValue(NSNull(), format: .bool) == nil)
        #expect(HomeCharacteristicValue(nil, format: .bool) == nil)
    }

    @Test func describesValuesWithNamesAndUnits() {
        let names = [HomeValueChoice(value: 0, title: "Unsecured"), HomeValueChoice(value: 1, title: "Secured")]
        #expect(HomeInspectorFormat.describe(.integer(1), units: nil, names: names) == "Secured (1)")
        #expect(HomeInspectorFormat.describe(.integer(50), units: "%") == "50 %")
        #expect(HomeInspectorFormat.describe(.bool(false), units: nil) == "false")
        #expect(HomeInspectorFormat.describe(.text("Hall"), units: nil) == "“Hall”")
        #expect(HomeInspectorFormat.describe(nil, units: "%") == "—")
    }

    @Test func picksTheWriteControlFromFormatAndMetadata() {
        #expect(HomeInspectorFormat.control(for: characteristic(format: .bool, properties: [.readable]), allowsSlider: true) == nil)
        #expect(HomeInspectorFormat.control(for: characteristic(format: .bool), allowsSlider: true) == .toggle)
        #expect(HomeInspectorFormat.control(for: characteristic(format: .string), allowsSlider: true) == .text(maxLength: nil))
        if case .unsupported = HomeInspectorFormat.control(for: characteristic(format: .tlv8), allowsSlider: true) {} else { Issue.record("TLV8 must not be writable") }
        if case .unsupported = HomeInspectorFormat.control(for: characteristic(format: .int), allowsSlider: true) {} else { Issue.record("No range, no names") }
        #expect(HomeInspectorFormat.control(for: characteristic(format: .float, minimum: 10, maximum: 38, step: 0.5), allowsSlider: true)
                == .slider(minimum: 10, maximum: 38, step: 0.5))
    }

    @Test func enumeratedValuesBecomeNamedChoices() {
        let names = [HomeValueChoice(value: 0, title: "Unsecured"), HomeValueChoice(value: 1, title: "Secured")]
        let lock = characteristic(format: .uint8, minimum: 0, maximum: 1, step: 1, names: names)
        #expect(HomeInspectorFormat.control(for: lock, allowsSlider: true)
                == .choice([HomeValueChoice(value: 0, title: "Unsecured (0)"), HomeValueChoice(value: 1, title: "Secured (1)")]))
        let valid = characteristic(format: .uint8, minimum: 0, maximum: 3, validValues: [0, 3])
        #expect(HomeInspectorFormat.control(for: valid, allowsSlider: true)
                == .choice([HomeValueChoice(value: 0, title: "0"), HomeValueChoice(value: 3, title: "3")]))
    }

    @Test func rangesWithoutSlidersBecomeElevenLevels() {
        guard case .levels(let levels) = HomeInspectorFormat.control(for: characteristic(format: .float, minimum: 0, maximum: 100, step: 1), allowsSlider: false) else {
            Issue.record("Expected levels"); return
        }
        #expect(levels == [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100])
        guard case .choice(let choices) = HomeInspectorFormat.control(for: characteristic(format: .int, minimum: 0, maximum: 100, step: 1, units: "%"), allowsSlider: false) else {
            Issue.record("Expected choices"); return
        }
        #expect(choices.count == 11)
        #expect(choices.first?.title == "0 %" && choices.last?.value == 100)
    }

    @Test func formatsTriggerTimes() {
        #expect(HomeInspectorFormat.recurrence(DateComponents(day: 1)) == "every day")
        #expect(HomeInspectorFormat.recurrence(DateComponents(hour: 2)) == "every 2 hours")
        #expect(HomeInspectorFormat.recurrence(nil) == "once")
        #expect(HomeInspectorFormat.weekdays([DateComponents(weekday: 3), DateComponents(weekday: 2)]) == "Mon, Tue")
        #expect(HomeInspectorFormat.weekdays((1...7).map { DateComponents(weekday: $0) }) == "every day")
        #expect(HomeInspectorFormat.timeOfDay(DateComponents(hour: 7, minute: 5)) == "07:05")
        #expect(HomeInspectorFormat.offset(DateComponents(minute: 30)) == " +30 min")
        #expect(HomeInspectorFormat.offset(DateComponents(hour: -1, minute: -15)) == " −1 h 15 min")
        #expect(HomeInspectorFormat.offset(nil) == "")
    }
}

#if canImport(HomeKit) && !os(macOS)
struct HomeCharacteristicCatalogTests {
    @Test func mapsHomeKitConstants() {
        #expect(HomeCharacteristicCatalog.format(HMCharacteristicMetadataFormatUInt8) == .uint8)
        #expect(HomeCharacteristicCatalog.format(HMCharacteristicMetadataFormatBool) == .bool)
        #expect(HomeCharacteristicCatalog.format(nil) == nil)
        #expect(HomeCharacteristicCatalog.properties([HMCharacteristicPropertyWritable, HMCharacteristicPropertyReadable]) == [.readable, .writable])
        #expect(HomeCharacteristicCatalog.unitSymbol(HMCharacteristicMetadataUnitsCelsius) == "°C")
        #expect(HomeCharacteristicCatalog.unitSymbol(HMCharacteristicMetadataUnitsPercentage) == "%")
        #expect(HomeCharacteristicCatalog.sceneTypeName(HMActionSetTypeUserDefined) == "User defined")
    }

    @Test func namesLockStatesAndConfirmsSecurityWrites() {
        #expect(HomeCharacteristicCatalog.namedValues(forType: HMCharacteristicTypeTargetLockMechanismState).map(\.title) == ["Unsecured", "Secured"])
        #expect(HomeCharacteristicCatalog.namedValues(forType: HMCharacteristicTypeBrightness).isEmpty)
        #expect(HomeCharacteristicCatalog.needsConfirmation(type: HMCharacteristicTypeTargetLockMechanismState))
        #expect(HomeCharacteristicCatalog.needsConfirmation(type: HMCharacteristicTypeTargetDoorState))
        #expect(!HomeCharacteristicCatalog.needsConfirmation(type: HMCharacteristicTypeCurrentLockMechanismState))
        #expect(!HomeCharacteristicCatalog.needsConfirmation(type: HMCharacteristicTypePowerState))
    }
}
#endif

struct AccessorySetupPayloadTests {

    @Test func recognizesMatterQRCode() {
        #expect(AccessorySetupPayloadKind.classify(" MT:Y.K9042C00KA0648G00 ") == .matterQRCode("MT:Y.K9042C00KA0648G00"))
    }

    @Test func normalizesManualPairingCodes() {
        #expect(AccessorySetupPayloadKind.classify("3497-011-2332") == .matterManualCode("34970112332"))
        #expect(AccessorySetupPayloadKind.classify("749701123365521327694") == .matterManualCode("749701123365521327694"))
        #expect(AccessorySetupPayloadKind.classify("1234-5678") == nil)
    }

    @Test func recognizesHomeKitSetupURL() {
        let kind = AccessorySetupPayloadKind.classify("X-HM://0023ISYWY1ABCD")
        #expect(kind == .homeKitURL("X-HM://0023ISYWY1ABCD"))
        #expect(kind?.isMatter == false)
    }

    @Test func rejectsOtherText() {
        #expect(AccessorySetupPayloadKind.classify("") == nil)
        #expect(AccessorySetupPayloadKind.classify("MT:") == nil)
        #expect(AccessorySetupPayloadKind.classify("https://example.com") == nil)
    }

    @Test func payloadModesNameTheirEntitlement() {
        #expect(AccessorySetupMode.systemFlow.requiredEntitlement == nil)
        #expect(AccessorySetupMode.matterPayload.requiredEntitlement == "com.apple.developer.matter.allow-setup-payload")
        #expect(AccessorySetupMode.homeKitURL.requiredEntitlement == "com.apple.developer.homekit.allow-setup-payload")
    }
}
