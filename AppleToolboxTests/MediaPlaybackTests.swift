import Testing
import Foundation
@testable import AppleToolbox

struct MediaPlaybackTests {

    @Test func sampleStreamsAreApplesHTTPSPlaylists() {
        for stream in HLSSampleStream.allCases {
            #expect(stream.url.scheme == "https", "\(stream)")
            #expect(stream.url.host == "devstreaming-cdn.apple.com", "\(stream)")
            #expect(stream.url.pathExtension == "m3u8", "\(stream)")
        }
        #expect(Set(HLSSampleStream.allCases.map(\.url)).count == HLSSampleStream.allCases.count)
    }

    @Test func nextAndPreviousStreamWrapAround() {
        let all = HLSSampleStream.allCases
        #expect(all.first?.neighbor(offset: -1) == all.last)
        #expect(all.last?.neighbor(offset: 1) == all.first)
        #expect(all[0].neighbor(offset: 1) == all[1])
        #expect(all[1].neighbor(offset: all.count) == all[1])
    }

    @Test func clockFormatsMinutesAndHours() {
        #expect(MediaPlaybackService.clock(0) == "0:00")
        #expect(MediaPlaybackService.clock(65.9) == "1:05")
        #expect(MediaPlaybackService.clock(3_725) == "1:02:05")
        #expect(MediaPlaybackService.clock(.nan) == "—")
        #expect(MediaPlaybackService.clock(-1) == "—")
    }

    @Test func remoteCommandKindsCoverBothSkipStyles() {
        let titles = Set(RemoteCommandKind.allCases.map(\.title))
        #expect(titles.count == RemoteCommandKind.allCases.count)
        #expect(RemoteCommandKind.allCases.contains(.skipForward) && RemoteCommandKind.allCases.contains(.nextTrack))
    }
}
