import Testing
import Foundation
#if canImport(HealthKit)
import HealthKit
#endif
@testable import AppleToolbox

struct HealthReaderFormatTests {
    @Test func turnsTypeIdentifiersIntoNames() {
        #expect(HealthReaderFormat.typeName("HKQuantityTypeIdentifierHeartRateVariabilitySDNN") == "Heart Rate Variability SDNN")
        #expect(HealthReaderFormat.typeName("HKQuantityTypeIdentifierVO2Max") == "VO2 Max")
        #expect(HealthReaderFormat.typeName("HKQuantityTypeIdentifierUVExposure") == "UV Exposure")
        #expect(HealthReaderFormat.typeName("HKCategoryTypeIdentifierSleepAnalysis") == "Sleep Analysis")
        #expect(HealthReaderFormat.typeName("HKWorkoutTypeIdentifier") == "Workouts")
    }

    @Test func addsUpSleepStages() {
        let totals = HealthReaderFormat.sleepTotals([(stage: 3, seconds: 600), (stage: 4, seconds: 300), (stage: 3, seconds: 900), (stage: 2, seconds: -5)])
        #expect(totals.map(\.stage) == [2, 3, 4])
        #expect(totals.map(\.seconds) == [0, 1500, 300])
        #expect(HealthReaderFormat.sleepStageName(5) == "REM")
        #expect(HealthReaderFormat.sleepStageName(9) == "Sleep value 9")
    }

    @Test func formatsValuesAndErrors() {
        #expect(HealthReaderFormat.value(72, display: HealthUnitDisplay(label: "bpm")) == "72 bpm")
        #expect(HealthReaderFormat.value(0.97, display: HealthUnitDisplay(label: "%", scale: 100, fractionDigits: 1)) == "97 %")
        #expect(HealthReaderFormat.errorName(5) == "errorAuthorizationNotDetermined")
        let error = NSError(domain: "com.apple.healthkit", code: 6, userInfo: [NSLocalizedDescriptionKey: "Locked"])
        #expect(HealthReaderFormat.errorText(error) == "HKError 6 (errorDatabaseInaccessible (device locked)): Locked")
    }
}

#if canImport(HealthKit) && os(iOS)
struct HealthReaderCatalogTests {
    @Test func namesMatchHealthKitRawValues() {
        #expect(HKErrorDomain == "com.apple.healthkit")
        #expect(HealthReaderFormat.errorName(HKError.Code.errorAuthorizationNotDetermined.rawValue) == "errorAuthorizationNotDetermined")
        #expect(HealthReaderFormat.errorName(HKError.Code.errorNoData.rawValue) == "errorNoData")
        #expect(HealthReaderFormat.sleepStageName(HKCategoryValueSleepAnalysis.asleepDeep.rawValue) == "Deep")
        #expect(HealthReaderFormat.sleepStageName(HKCategoryValueSleepAnalysis.inBed.rawValue) == "In bed")
        #expect(HealthReaderCatalog.activityName(.running) == "Running")
    }

    @Test func everyPresetReadsDistinctTypes() {
        for preset in HealthReaderPreset.allCases {
            let identifiers = preset.sampleTypes.map(\.identifier)
            #expect(!identifiers.isEmpty, "\(preset)")
            #expect(Set(identifiers).count == identifiers.count, "\(preset)")
        }
        #expect(HealthReaderPreset.workouts.sampleTypes.contains(HKWorkoutType.workoutType()))
        #expect(HealthReaderPreset.activity.quantityTypes.contains(.stepCount))
        #expect(HealthReaderPreset.sleep.categoryTypes == [.sleepAnalysis])
    }

    @Test func everyQuantityHasACompatibleUnit() {
        for identifier in Set(HealthReaderPreset.allCases.flatMap(\.quantityTypes)) {
            let unit = HealthReaderCatalog.unit(for: identifier)?.unit
            #expect(unit != nil, "\(identifier.rawValue)")
            if let unit { #expect(HKQuantityType(identifier).is(compatibleWith: unit), "\(identifier.rawValue)") }
        }
    }

    @Test func convertsQuantities() {
        let heartRate = HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 64)
        #expect(HealthReaderCatalog.quantityText(heartRate, identifier: .heartRate) == "64 bpm")
        let steps = HKQuantity(unit: .count(), doubleValue: 950)
        #expect(HealthReaderCatalog.quantityText(steps, identifier: .stepCount) == "950 steps")
        #expect(HealthDeliveryFrequency.hourly.updateFrequency == .hourly)
    }
}
#endif
