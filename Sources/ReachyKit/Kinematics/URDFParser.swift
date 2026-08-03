import Foundation
import simd

public enum URDFParseError: Error, Equatable, LocalizedError {
    case malformedXML(line: Int, column: Int, message: String)
    case missingRobotElement
    case missingAttribute(element: String, attribute: String)
    case unknownJointType(String)
    case unknownLink(String, referencedBy: String)
    case notASingleRootedTree(rootCount: Int)

    public var errorDescription: String? {
        switch self {
        case let .malformedXML(line, column, message):
            "Malformed URDF at \(line):\(column) — \(message)"
        case .missingRobotElement:
            "URDF has no <robot> element"
        case let .missingAttribute(element, attribute):
            "URDF <\(element)> is missing the \(attribute) attribute"
        case let .unknownJointType(type):
            "Unsupported URDF joint type: \(type)"
        case let .unknownLink(link, joint):
            "URDF joint \(joint) references undeclared link \(link)"
        case let .notASingleRootedTree(count):
            "URDF must have exactly one root link, found \(count)"
        }
    }
}

/// Streaming URDF reader.
///
/// `XMLParser` rather than `XMLDocument`: the latter is macOS-only, and this
/// package ships to iOS too. Streaming also avoids building a DOM for a document
/// that is mostly inertia and collision data we discard.
public enum URDFParser {
    public static func parse(_ data: Data) throws -> URDFDocument {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            if let failure = delegate.failure {
                throw failure
            }
            let error = parser.parserError
            throw URDFParseError.malformedXML(
                line: parser.lineNumber,
                column: parser.columnNumber,
                message: error?.localizedDescription ?? "unknown error"
            )
        }
        if let failure = delegate.failure {
            throw failure
        }
        guard let name = delegate.robotName else {
            throw URDFParseError.missingRobotElement
        }
        return try URDFDocument(name: name, links: delegate.links, joints: delegate.joints)
    }

    public static func parse(_ xml: String) throws -> URDFDocument {
        try parse(Data(xml.utf8))
    }
}

private extension URDFParser {
    /// Mutable scratch state for one link, joint or visual being read.
    struct LinkBuilder {
        var name: String
        var visuals: [URDFVisual] = []
    }

    struct VisualBuilder {
        var origin: URDFPose = .identity
        var geometry: URDFGeometry?
        var color: URDFColor?
    }

    struct JointBuilder {
        var name: String
        var kind: URDFJoint.Kind
        var parent: String?
        var child: String?
        var origin: URDFPose = .identity
        var axis = SIMD3<Double>(1, 0, 0)
        var limit: ClosedRange<Double>?
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var robotName: String?
        var links: [URDFLink] = []
        var joints: [URDFJoint] = []
        var failure: URDFParseError?

        private var link: LinkBuilder?
        private var visual: VisualBuilder?
        private var joint: JointBuilder?
        /// `<collision>` mirrors `<visual>` element for element; skipping the whole
        /// subtree is what keeps collision meshes out of the download list.
        private var skipDepth = 0

        func parser(
            _ parser: XMLParser,
            didStartElement element: String,
            namespaceURI _: String?,
            qualifiedName _: String?,
            attributes: [String: String]
        ) {
            guard failure == nil else { return }
            if skipDepth > 0 {
                skipDepth += 1
                return
            }
            do {
                try start(element, attributes: attributes)
            } catch let error as URDFParseError {
                failure = error
                parser.abortParsing()
            } catch {
                failure = .malformedXML(line: parser.lineNumber, column: parser.columnNumber, message: "\(error)")
                parser.abortParsing()
            }
        }

        func parser(
            _: XMLParser,
            didEndElement element: String,
            namespaceURI _: String?,
            qualifiedName _: String?
        ) {
            guard failure == nil else { return }
            if skipDepth > 0 {
                skipDepth -= 1
                return
            }
            end(element)
        }

        private func start(_ element: String, attributes: [String: String]) throws {
            switch element {
            case "robot":
                robotName = attributes["name"] ?? "robot"
            case "inertial", "collision":
                skipDepth = 1
            case "link":
                link = try LinkBuilder(name: attribute("name", of: element, in: attributes))
            case "visual":
                visual = VisualBuilder()
            case "joint":
                try startJoint(attributes)
            case "origin":
                let pose = URDFPose(
                    xyz: Self.vector(attributes["xyz"]) ?? .zero,
                    rpy: Self.vector(attributes["rpy"]) ?? .zero
                )
                // A link's `<inertial>` is skipped wholesale, so an origin seen
                // while a visual is open always belongs to that visual.
                if visual != nil {
                    visual?.origin = pose
                } else {
                    joint?.origin = pose
                }
            default:
                try startGeometry(element, attributes: attributes)
                startJointDetail(element, attributes: attributes)
            }
        }

        /// `<joint>` also appears inside `<transmission>`, where it carries no type.
        private func startJoint(_ attributes: [String: String]) throws {
            guard let name = attributes["name"], let rawType = attributes["type"] else {
                skipDepth = 1
                return
            }
            guard let kind = URDFJoint.Kind(rawValue: rawType) else {
                throw URDFParseError.unknownJointType(rawType)
            }
            joint = JointBuilder(name: name, kind: kind)
        }

        private func startGeometry(_ element: String, attributes: [String: String]) throws {
            switch element {
            case "mesh":
                let filename = try attribute("filename", of: element, in: attributes)
                visual?.geometry = .mesh(
                    filename: Self.strippedPackagePrefix(filename),
                    scale: Self.vector(attributes["scale"]) ?? SIMD3(1, 1, 1)
                )
            case "box":
                visual?.geometry = .box(size: Self.vector(attributes["size"]) ?? .zero)
            case "cylinder":
                visual?.geometry = .cylinder(
                    radius: Self.scalar(attributes["radius"]) ?? 0,
                    length: Self.scalar(attributes["length"]) ?? 0
                )
            case "sphere":
                visual?.geometry = .sphere(radius: Self.scalar(attributes["radius"]) ?? 0)
            case "color":
                visual?.color = Self.color(attributes["rgba"])
            default:
                break
            }
        }

        private func startJointDetail(_ element: String, attributes: [String: String]) {
            switch element {
            case "parent":
                joint?.parent = attributes["link"]
            case "child":
                joint?.child = attributes["link"]
            case "axis":
                if let axis = Self.vector(attributes["xyz"]) {
                    joint?.axis = axis
                }
            case "limit":
                if let lower = Self.scalar(attributes["lower"]),
                   let upper = Self.scalar(attributes["upper"]), lower <= upper
                {
                    joint?.limit = lower ... upper
                }
            default:
                break
            }
        }

        private func end(_ element: String) {
            switch element {
            case "visual":
                if let visual, let geometry = visual.geometry {
                    link?.visuals.append(
                        URDFVisual(origin: visual.origin, geometry: geometry, color: visual.color)
                    )
                }
                visual = nil
            case "link":
                if let link {
                    links.append(URDFLink(name: link.name, visuals: link.visuals))
                }
                link = nil
            case "joint":
                if let joint, let parent = joint.parent, let child = joint.child {
                    joints.append(URDFJoint(
                        name: joint.name,
                        kind: joint.kind,
                        parent: parent,
                        child: child,
                        origin: joint.origin,
                        axis: joint.axis,
                        limit: joint.limit
                    ))
                }
                joint = nil
            default:
                break
            }
        }

        private func attribute(
            _ name: String,
            of element: String,
            in attributes: [String: String]
        ) throws -> String {
            guard let value = attributes[name] else {
                throw URDFParseError.missingAttribute(element: element, attribute: name)
            }
            return value
        }

        /// `Double(_:)` is locale-independent; `NumberFormatter` is not, and URDF
        /// is always written with a dot.
        private static func numbers(_ raw: String?) -> [Double]? {
            guard let raw else { return nil }
            let parts = raw.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
            return parts.isEmpty ? nil : parts
        }

        private static func vector(_ raw: String?) -> SIMD3<Double>? {
            guard let values = numbers(raw), values.count >= 3 else { return nil }
            return SIMD3(values[0], values[1], values[2])
        }

        private static func scalar(_ raw: String?) -> Double? {
            numbers(raw)?.first
        }

        private static func color(_ raw: String?) -> URDFColor? {
            guard let values = numbers(raw), values.count >= 4 else { return nil }
            return URDFColor(red: values[0], green: values[1], blue: values[2], alpha: values[3])
        }

        /// `package://assets/base.stl` names the file `base.stl` on the daemon's
        /// STL route; the package segment is meaningless to us.
        private static func strippedPackagePrefix(_ filename: String) -> String {
            guard let range = filename.range(of: "://") else { return filename }
            let afterScheme = filename[range.upperBound...]
            guard let slash = afterScheme.firstIndex(of: "/") else { return String(afterScheme) }
            return String(afterScheme[afterScheme.index(after: slash)...])
        }
    }
}
