import Foundation
import Testing
@testable import FieldWeaveCore
@Suite struct FieldWeaveConfigurationImportTests {
    @Test func unknownAndInactiveConfigurationCannotSilentlyDisappear() throws {
        let data=try FieldConfiguration().jsonData()
        let reopened=try FieldConfiguration.decode(data)
        #expect(reopened == FieldConfiguration())
        var object=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
        object["room_distance"]=5
        #expect(throws:Error.self) {try FieldConfiguration.decode(JSONSerialization.data(withJSONObject:object))}
        object.removeValue(forKey:"room_distance")
        var safety=try #require(object["safety"] as? [String:Any]);safety["fake_limiter"]=true;object["safety"]=safety
        #expect(throws:Error.self) {try FieldConfiguration.decode(JSONSerialization.data(withJSONObject:object))}
    }
}
