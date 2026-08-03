import Foundation
@testable import ReachyKit
import Testing

@Suite("Kinematics info")
struct KinematicsInfoTests {
    private func decode(_ json: String) throws -> KinematicsInfo {
        try JSONDecoder().decode(KinematicsInfo.self, from: Data(json.utf8))
    }

    /// Note the nesting and the space inside the second key — both come straight
    /// from the daemon and neither would survive synthesised coding keys.
    @Test("decodes the daemon's nested payload")
    func decodesDefaultEngine() throws {
        let info = try decode(#"{"info": {"engine": "AnalyticalKinematics", "collision check": false}}"#)
        #expect(info.engine == "AnalyticalKinematics")
        #expect(info.checksCollisions == false)
        #expect(info.providesPassiveJoints == false)
    }

    @Test("recognises the one engine that fills passive joints")
    func recognisesPlaco() throws {
        let info = try decode(#"{"info": {"engine": "Placo", "collision check": true}}"#)
        #expect(info.checksCollisions)
        #expect(info.providesPassiveJoints)
    }

    @Test("a missing collision flag is not an error")
    func toleratesMissingCollisionFlag() throws {
        #expect(try decode(#"{"info": {"engine": "NN"}}"#).checksCollisions == false)
    }
}
