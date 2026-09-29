import Testing
import Foundation
#if canImport(MapKit)
import MapKit
#endif
@testable import AppleToolbox

struct MapsLabTests {

    @Test func onlyTransitLacksRouteGeometry() {
        #expect(MapsTransport.allCases.filter { !$0.providesRouteGeometry } == [.transit])
    }

    #if canImport(MapKit)
    @Test func transportMapsToDirectionsTypes() {
        #expect(MapsTransport.automobile.directionsType == .automobile)
        #expect(MapsTransport.walking.directionsType == .walking)
        #expect(MapsTransport.transit.directionsType == .transit)
        #expect(MapsTransport.cycling.directionsType == .cycling)
    }
    #endif

    @Test func formatsTravelTimes() {
        #expect(MapsLabText.travelTime(0) == "0 min")
        #expect(MapsLabText.travelTime(20) == "1 min")
        #expect(MapsLabText.travelTime(90) == "2 min")
        #expect(MapsLabText.travelTime(3_900) == "1 h 05 min")
    }

    @Test func formatsDistances() {
        #expect(MapsLabText.distance(949.6) == "950 m")
        #expect(MapsLabText.distance(12_345).hasSuffix(" km"))
    }

    @Test func turnsPointOfInterestCategoriesIntoWords() {
        #expect(MapsLabText.category("MKPOICategoryPublicTransport") == "Public Transport")
        #expect(MapsLabText.category("MKPOICategoryEVCharger") == "EV Charger")
        #expect(MapsLabText.category("MKPOICategoryATM") == "ATM")
        #expect(MapsLabText.category("Cafe") == "Cafe")
    }
}
