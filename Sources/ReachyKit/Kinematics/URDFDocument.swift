import Foundation
import simd

/// The subset of URDF this client needs to draw a robot: a link tree, joint
/// frames, and which mesh belongs where.
///
/// Inertia, collision geometry, transmissions and Gazebo extensions are dropped
/// while parsing — nothing here simulates physics.
public struct URDFDocument: Sendable, Equatable {
    public let name: String
    public let links: [URDFLink]
    public let joints: [URDFJoint]

    private let linksByName: [String: URDFLink]
    private let jointsByName: [String: URDFJoint]
    private let jointsByParent: [String: [URDFJoint]]
    private let parentJoint: [String: URDFJoint]

    /// The one link no joint lists as a child.
    public let rootLinkName: String

    public init(name: String, links: [URDFLink], joints: [URDFJoint]) throws {
        self.name = name
        self.links = links
        self.joints = joints
        let byName = Dictionary(links.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let byChild = Dictionary(joints.map { ($0.child, $0) }, uniquingKeysWith: { first, _ in first })

        for joint in joints {
            guard byName[joint.parent] != nil else {
                throw URDFParseError.unknownLink(joint.parent, referencedBy: joint.name)
            }
            guard byName[joint.child] != nil else {
                throw URDFParseError.unknownLink(joint.child, referencedBy: joint.name)
            }
        }
        let roots = links.map(\.name).filter { byChild[$0] == nil }
        guard roots.count == 1, let root = roots.first else {
            throw URDFParseError.notASingleRootedTree(rootCount: roots.count)
        }

        linksByName = byName
        parentJoint = byChild
        jointsByName = Dictionary(joints.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        jointsByParent = Dictionary(grouping: joints, by: \.parent)
        rootLinkName = root
    }

    public func link(named name: String) -> URDFLink? {
        linksByName[name]
    }

    public func joint(named name: String) -> URDFJoint? {
        jointsByName[name]
    }

    public func childJoints(of link: String) -> [URDFJoint] {
        jointsByParent[link] ?? []
    }

    /// Joints that actually move, in declaration order.
    public var movableJoints: [URDFJoint] {
        joints.filter(\.kind.isMovable)
    }

    /// Every distinct mesh referenced by a `<visual>`. Collision geometry is never
    /// parsed, so it cannot leak in here and cause needless downloads.
    public var visualMeshFilenames: Set<String> {
        var names: Set<String> = []
        for link in links {
            for visual in link.visuals {
                if case let .mesh(filename, _) = visual.geometry {
                    names.insert(filename)
                }
            }
        }
        return names
    }
}

public struct URDFLink: Sendable, Equatable {
    public let name: String
    public let visuals: [URDFVisual]

    public init(name: String, visuals: [URDFVisual]) {
        self.name = name
        self.visuals = visuals
    }
}

public struct URDFVisual: Sendable, Equatable {
    public let origin: URDFPose
    public let geometry: URDFGeometry
    public let color: URDFColor?

    public init(origin: URDFPose, geometry: URDFGeometry, color: URDFColor?) {
        self.origin = origin
        self.geometry = geometry
        self.color = color
    }
}

public enum URDFGeometry: Sendable, Equatable {
    /// `filename` has the `package://<pkg>/` prefix stripped — it is what the
    /// daemon's STL route expects.
    case mesh(filename: String, scale: SIMD3<Double>)
    case box(size: SIMD3<Double>)
    case cylinder(radius: Double, length: Double)
    case sphere(radius: Double)
}

public struct URDFJoint: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case fixed, revolute, continuous, prismatic, floating, planar

        public var isMovable: Bool {
            switch self {
            case .fixed: false
            default: true
            }
        }
    }

    public let name: String
    public let kind: Kind
    public let parent: String
    public let child: String
    public let origin: URDFPose
    /// Normalised. URDF's default when `<axis>` is absent is (1, 0, 0).
    public let axis: SIMD3<Double>
    public let limit: ClosedRange<Double>?

    public init(
        name: String,
        kind: Kind,
        parent: String,
        child: String,
        origin: URDFPose,
        axis: SIMD3<Double>,
        limit: ClosedRange<Double>?
    ) {
        self.name = name
        self.kind = kind
        self.parent = parent
        self.child = child
        self.origin = origin
        let length = simd_length(axis)
        self.axis = length > 0 ? axis / length : SIMD3(1, 0, 0)
        self.limit = limit
    }
}

/// A frame offset: translation plus roll/pitch/yaw, both in URDF units
/// (metres and radians).
public struct URDFPose: Sendable, Equatable, Hashable {
    public let xyz: SIMD3<Double>
    public let rpy: SIMD3<Double>

    public static let identity = URDFPose(xyz: .zero, rpy: .zero)

    public init(xyz: SIMD3<Double>, rpy: SIMD3<Double>) {
        self.xyz = xyz
        self.rpy = rpy
    }

    public var matrix: simd_double4x4 {
        RigidTransform.transform(translation: xyz, rpy: rpy)
    }
}

public struct URDFColor: Sendable, Equatable, Hashable {
    public let red, green, blue, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
