/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import struct PackageModel.PackageReference
import struct SPMUtility.Version
import class Foundation.NSDate

public enum DependencyResolverError: Error, Equatable, CustomStringConvertible {
    /// The resolver was unable to find a solution to the input constraints.
    case unsatisfiable

    /// The resolver found a dependency cycle.
    case cycle(PackageReference)

    /// The resolver encountered a versioned container which has a revision dependency.
    case incompatibleConstraints(
        dependency: (PackageReference, String),
        revisions: [(PackageReference, String)])

    /// The resolver found missing versions for the given constraints.
    case missingVersions([PackageContainerConstraint])

    /// A revision-based dependency contains a local package dependency.
    case revisionDependencyContainsLocalPackage(dependency: String, localPackage: String)

    /// The resolution was cancelled.
    case cancelled

    public static func == (lhs: DependencyResolverError, rhs: DependencyResolverError) -> Bool {
        switch (lhs, rhs) {
        case (.unsatisfiable, .unsatisfiable):
            return true
        case (.unsatisfiable, _):
            return false
        case (.cycle(let lhs), .cycle(let rhs)):
            return lhs == rhs 
        case (.cycle, _):
            return false
        case (.incompatibleConstraints(let lDependency, let lRevisions),
              .incompatibleConstraints(let rDependency, let rRevisions)):
            return lDependency == rDependency && lRevisions == rRevisions
        case (.incompatibleConstraints, _):
            return false
        case (.missingVersions(let lhs), .missingVersions(let rhs)):
            return lhs == rhs
        case (.missingVersions, _):
            return false
        case (.revisionDependencyContainsLocalPackage(let a1, let b1), .revisionDependencyContainsLocalPackage(let a2, let b2)):
            return a1 == a2 && b1 == b2
        case (.revisionDependencyContainsLocalPackage, _):
            return false
        case (.cancelled, .cancelled):
            return true
        case (.cancelled, _):
            return false
        }
    }

    public var description: String {
        switch self {
        case .cancelled:
            return "the package resolution operation was cancelled"
        case .revisionDependencyContainsLocalPackage(let dependency, let localPackage):
            return "package '\(dependency)' is required using a revision-based requirement and it depends on local package '\(localPackage)', which is not supported"
        case .unsatisfiable:
            return "the package dependency graph could not be resolved due to an unknown conflict"
        case .cycle(let package):
            return "the package \(package) depends on itself"
        case let .incompatibleConstraints(dependency, revisions):
            let stream = BufferedOutputByteStream()
            stream <<< "the package \(dependency.0) @ \(dependency.1) contains incompatible dependencies:\n"
            for (i, revision) in revisions.enumerated() {
                stream <<< "    "
                stream <<< "\(revision.0)" <<< " @ " <<< revision.1
                if i != revisions.count - 1 {
                    stream  <<< "\n"
                }
            }
            return stream.bytes.description

        case let .missingVersions(constraints):
            let stream = BufferedOutputByteStream()
            stream <<< "the package dependency graph could not be resolved; unable to find any available tag for the following requirements:\n"
            for (i, constraint) in constraints.enumerated() {
                stream <<< "    "
                stream <<< "\(constraint.identifier.path)" <<< " @ "
                switch constraint.requirement {
                case .versionSet(let set):
                    stream <<< "\(set)"
                case .revision, .unversioned:
                    assertionFailure("Unexpected requirement type")
                    break
                }
                if i != constraints.count - 1 {
                    stream  <<< "\n"
                }
            }
            return stream.bytes.description
        }
    }
}

/// A requirement that a package must satisfy.
public enum PackageRequirement: Hashable {

    /// The requirement is specified by the version set.
    case versionSet(VersionSetSpecifier)

    /// The requirement is specified by the revision.
    ///
    /// The revision string (identifier) should be valid and present in the
    /// container. Only one revision requirement per container is possible
    /// i.e. two revision requirements for same container will lead to
    /// unsatisfiable resolution. The revision requirement can either come
    /// from initial set of constraints or from dependencies of a revision
    /// requirement.
    case revision(String)

    /// Un-versioned requirement i.e. a version should not resolved.
    case unversioned
}

extension PackageRequirement: CustomStringConvertible {
    public var description: String {
        switch self {
        case .versionSet(let versionSet): return versionSet.description
        case .revision(let revision): return revision
        case .unversioned: return "unversioned"
        }
    }
}

/// A container of packages.
///
/// This is the top-level unit of package resolution, i.e. the unit at which
/// versions are associated.
///
/// It represents a package container (e.g., a source repository) which can be
/// identified unambiguously and which contains a set of available package
/// versions and the ability to retrieve the dependency constraints for each of
/// those versions.
///
/// We use the "container" terminology here to differentiate between two
/// conceptual notions of what the package is: (1) informally, the repository
/// containing the package, but from which a package cannot be loaded by itself
/// and (2) the repository at a particular version, at which point the package
/// can be loaded and dependencies enumerated.
///
/// This is also designed in such a way to extend naturally to multiple packages
/// being contained within a single repository, should we choose to support that
/// later.
public protocol PackageContainer {

    /// The identifier for the package.
    var identifier: PackageReference { get }

    /// Returns true if the tools version is compatible at the given version.
    func isToolsVersionCompatible(at version: Version) -> Bool

    /// Get the list of versions which are available for the package.
    ///
    /// The list will be returned in sorted order, with the latest version *first*.
    /// All versions will not be requested at once. Resolver will request the next one only 
    /// if the previous one did not satisfy all constraints.
    func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version>

    /// Get the list of versions in the repository sorted in the reverse order, that is the latest
    /// version appears first.
    var reversedVersions: [Version] { get }

    // FIXME: We should perhaps define some particularly useful error codes
    // here, so the resolver can handle errors more meaningfully.
    //
    /// Fetch the declared dependencies for a particular version.
    ///
    /// This property is expected to be efficient to access, and cached by the
    /// client if necessary.
    ///
    /// - Precondition: `versions.contains(version)`
    /// - Throws: If the version could not be resolved; this will abort
    ///   dependency resolution completely.
    func getDependencies(at version: Version) throws -> [PackageContainerConstraint]

    /// Fetch the declared dependencies for a particular revision.
    ///
    /// This property is expected to be efficient to access, and cached by the
    /// client if necessary.
    ///
    /// - Throws: If the revision could not be resolved; this will abort
    ///   dependency resolution completely.
    func getDependencies(at revision: String) throws -> [PackageContainerConstraint]

    /// Fetch the dependencies of an unversioned package container.
    ///
    /// NOTE: This method should not be called on a versioned container.
    func getUnversionedDependencies() throws -> [PackageContainerConstraint]

    /// Get the updated identifier at a bound version.
    ///
    /// This can be used by the containers to fill in the missing information that is obtained
    /// after the container is available. The updated identifier is returned in result of the
    /// dependency resolution.
    func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference

    /// Hack for the old resolver. Don't use.
    var _isRemoteContainer: Bool? { get }
}

extension PackageContainer {
    public var _isRemoteContainer: Bool? { return nil }
}

/// An interface for resolving package containers.
public protocol PackageContainerProvider {
    /// Get the container for a particular identifier asynchronously.
    func getContainer(
        for identifier: PackageReference,
        skipUpdate: Bool,
        completion: @escaping (Result<PackageContainer, AnyError>) -> Void
    )
}

/// An individual constraint onto a container.
public struct PackageContainerConstraint: CustomStringConvertible, Equatable, Hashable {

    /// The identifier for the container the constraint is on.
    public let identifier: PackageReference

    /// The constraint requirement.
    public let requirement: PackageRequirement

    /// Create a constraint requiring the given `container` satisfying the
    /// `requirement`.
    public init(container identifier: PackageReference, requirement: PackageRequirement) {
        self.identifier = identifier
        self.requirement = requirement
    }

    /// Create a constraint requiring the given `container` satisfying the
    /// `versionRequirement`.
    public init(container identifier: PackageReference, versionRequirement: VersionSetSpecifier) {
        self.init(container: identifier, requirement: .versionSet(versionRequirement))
    }

    public var description: String {
        return "Constraint(\(identifier), \(requirement))"
    }
}

/// Delegate interface for dependency resoler status.
public protocol DependencyResolverDelegate {
}

// FIXME: This should be nested, but cannot be currently.
//
/// A bound version for a package within an assignment.
public enum BoundVersion: Equatable, CustomStringConvertible {
    /// The assignment should not include the package.
    ///
    /// This is different from the absence of an assignment for a particular
    /// package, which only indicates the assignment is agnostic to its
    /// version. This value signifies the package *may not* be present.
    case excluded

    /// The version of the package to include.
    case version(Version)

    /// The package assignment is unversioned.
    case unversioned

    /// The package assignment is this revision.
    case revision(String)

    public var description: String {
        switch self {
        case .excluded:
            return "excluded"
        case .version(let version):
            return version.description
        case .unversioned:
            return "unversioned"
        case .revision(let identifier):
            return identifier
        }
    }
}

// FIXME: Maybe each package should just return this, instead of a list of
// `PackageContainerConstraint`s. That won't work if we decide this should
// eventually map based on the `Container` rather than the `Identifier`, though,
// so they are separate for now.
//
/// A container for constraints for a set of packages.
///
/// This data structure is only designed to represent satisfiable constraint
/// sets, it cannot represent sets including containers which have an empty
/// constraint.
public struct PackageContainerConstraintSet: Collection, Hashable {

    public typealias Index = Dictionary<PackageReference, PackageRequirement>.Index
    public typealias Element = Dictionary<PackageReference, PackageRequirement>.Element

    /// The set of constraints.
    private var constraints: [PackageReference: PackageRequirement]

    /// Create an empty constraint set.
    public init() {
        self.constraints = [:]
    }

    /// Create an constraint set from known values.
    ///
    /// The initial constraints should never be unsatisfiable.
    init(_ constraints: [PackageReference: PackageRequirement]) {
        assert(constraints.values.filter({ $0 == .versionSet(.empty) }).isEmpty)
        self.constraints = constraints
    }

    /// The list of containers with entries in the set.
    var containerIdentifiers: AnySequence<PackageReference> {
        return AnySequence(constraints.keys)
    }

    /// Get the version set specifier associated with the given package `identifier`.
    public subscript(identifier: PackageReference) -> PackageRequirement {
        return constraints[identifier] ?? .versionSet(.any)
    }

    /// Create a constraint set by merging the `requirement` for container `identifier`.
    ///
    /// - Returns: The new set, or nil the resulting set is unsatisfiable.
    private func merging(
        requirement: PackageRequirement, for identifier: PackageReference
    ) -> PackageContainerConstraintSet? {
        switch (requirement, self[identifier]) {
        case (.versionSet(let newSet), .versionSet(let currentSet)):
            // Try to intersect two version set requirements.
            let intersection = currentSet.intersection(newSet)
            if intersection == .empty {
                return nil
            }
            var result = self
            result.constraints[identifier] = .versionSet(intersection)
            return result

        case (.unversioned, .unversioned):
            return self

        case (.unversioned, _):
            // Unversioned requirements always *wins*.
            var result = self
            result.constraints[identifier] = requirement
            return result

        case (_, .unversioned):
            // Unversioned requirements always *wins*.
            return self

        // The revision cases are deliberately placed below the unversioned
        // cases because unversioned has more priority.
        case (.revision(let lhs), .revision(let rhs)):
            // We can merge two revisions if they have the same identifier.
            if lhs == rhs { return self }
            return nil

        // We can merge the revision requiement if it currently does not have a requirement.
        case (.revision, .versionSet(.any)):
            var result = self
            result.constraints[identifier] = requirement
            return result

        // Otherwise, we can't merge the revision requirement.
        case (.revision, _):
            return nil

        // Exisiting revision requirements always *wins*.
        case (_, .revision):
            return self
        }
    }

    /// Create a constraint set by merging `constraint`.
    ///
    /// - Returns: The new set, or nil the resulting set is unsatisfiable.
    public func merging(_ constraint: PackageContainerConstraint) -> PackageContainerConstraintSet? {
        return merging(requirement: constraint.requirement, for: constraint.identifier)
    }

    /// Create a new constraint set by merging the given constraint set.
    ///
    /// - Returns: False if the merger has made the set unsatisfiable; i.e. true
    /// when the resulting set is satisfiable, if it was already so.
    func merging(
        _ constraints: PackageContainerConstraintSet
    ) -> PackageContainerConstraintSet? {
        var result = self
        for (key, requirement) in constraints {
            guard let merged = result.merging(requirement: requirement, for: key) else {
                return nil
            }
            result = merged
        }
        return result
    }

    // MARK: Collection Conformance

    public var startIndex: Index {
        return constraints.startIndex
    }

    public var endIndex: Index {
        return constraints.endIndex
    }

    public func index(after index: Index) -> Index {
        return constraints.index(after: index)
    }

    public subscript(position: Index) -> Element {
        return constraints[position]
    }
}

// FIXME: Actually make efficient.
//
/// A container for version assignments for a set of packages, exposed as a
/// sequence of `Container` to `BoundVersion` bindings.
///
/// This is intended to be an efficient data structure for accumulating a set of
/// version assignments along with efficient access to the derived information
/// about the assignment (for example, the unified set of constraints it
/// induces).
///
/// The set itself is designed to only ever contain a consistent set of
/// assignments, i.e. each assignment should satisfy the induced
/// `constraints`, but this invariant is not explicitly enforced.
struct VersionAssignmentSet: Equatable, Sequence {

    // FIXME: Does it really make sense to key on the identifier here. Should we
    // require referential equality of containers and use that to simplify?
    //
    /// The assignment records.
    fileprivate var assignments: OrderedDictionary<PackageReference, (container: PackageContainer, binding: BoundVersion)>

    /// Create an empty assignment.
    init() {
        assignments = [:]
    }

    /// The assignment for the given container `identifier.
    subscript(identifier: PackageReference) -> BoundVersion? {
        get {
            return assignments[identifier]?.binding
        }
    }

    /// The assignment for the given `container`.
    subscript(container: PackageContainer) -> BoundVersion? {
        get {
            return self[container.identifier]
        }
        set {
            // We disallow deletion.
            let newBinding = newValue!

            // Validate this is a valid assignment.
            assert(isValid(binding: newBinding, for: container))

            assignments[container.identifier] = (container: container, binding: newBinding)
        }
    }

    /// Create a new assignment set by merging in the bindings from `assignment`.
    ///
    /// - Returns: The new assignment, or nil if the merge cannot be made (the
    /// assignments contain incompatible versions).
    func merging(_ assignment: VersionAssignmentSet) -> VersionAssignmentSet? {
        // In order to protect the assignment set, we first have to test whether
        // the merged constraint sets are satisfiable.
        //
        // FIXME: This is very inefficient; we should decide whether it is right
        // to handle it here or force the main resolver loop to handle the
        // discovery of this property.
        guard constraints.merging(assignment.constraints) != nil else {
            return nil
        }

        // The induced constraints are satisfiable, so we *can* union the
        // assignments without breaking our internal invariant on
        // satisfiability.
        var result = self
        for (container, binding) in assignment {
            if let existing = result[container] {
                if existing != binding {
                    return nil
                }
            } else {
                result[container] = binding
            }
        }

        return result
    }

    // FIXME: We need to cache this.
    //
    /// The combined version constraints induced by the assignment.
    ///
    /// This consists of the merged constraints which need to be satisfied on
    /// each package as a result of the versions selected in the assignment.
    ///
    /// The resulting constraint set is guaranteed to be non-empty for each
    /// mapping, assuming the invariants on the set are followed.
    var constraints: PackageContainerConstraintSet {
        // Collect all of the constraints.
        var result = PackageContainerConstraintSet()

        /// Merge the provided constraints into result.
        func merge(constraints: [PackageContainerConstraint]) {
            for constraint in constraints {
                guard let merged = result.merging(constraint) else {
                    preconditionFailure("unsatisfiable constraint set")
                }
                result = merged
            }
        }

        for (_, (container: container, binding: binding)) in assignments {
            switch binding {
            case .unversioned, .excluded:
                // If the package is unversioned or excluded, it doesn't contribute.
                continue

            case .revision(let identifier):
                // FIXME: Need caching and error handling here. See the FIXME below.
                merge(constraints: try! container.getDependencies(at: identifier))

            case .version(let version):
                // If we have a version, add the constraints from that package version.
                //
                // FIXME: We should cache this too, possibly at a layer
                // different than above (like the entry record).
                //
                // FIXME: Error handling, except that we probably shouldn't have
                // needed to refetch the dependencies at this point.
                merge(constraints: try! container.getDependencies(at: version))
            }
        }
        return result
    }

    // FIXME: This is currently very inefficient.
    //
    /// Check if the given `binding` for `container` is valid within the assignment.
    func isValid(binding: BoundVersion, for container: PackageContainer) -> Bool {
        switch binding {
        case .excluded:
            // A package can be excluded if there are no constraints on the
            // package (it has not been requested by any other package in the
            // assignment).
            return constraints[container.identifier] == .versionSet(.any)

        case .version(let version):
            // A version is valid if it is contained in the constraints.
            if case .versionSet(let versionSet) = constraints[container.identifier] {
                return versionSet.contains(version)
            }
            return false

        case .revision(let identifier):
            // If we already have a revision constraint, it should be same as
            // the one we're trying to set.
            if case .revision(let existingRevision) = constraints[container.identifier] {
                return existingRevision == identifier
            }
            // Otherwise, it is always valid to set a revision binding. Note
            // that there are rules that prevents versioned constraints from
            // having revision constraints, but that is handled by the resolver.
            return true

        case .unversioned:
            // An unversioned binding is always valid.
            return true
        }
    }

    /// Check if the assignment is valid and complete.
    func checkIfValidAndComplete() -> Bool {
        // Validity should hold trivially, because it is an invariant of the collection.
        for (_, assignment) in assignments {
            if !isValid(binding: assignment.binding, for: assignment.container) {
                return false
            }
        }

        // Check completeness, by simply looking at all the entries in the induced constraints.
        for identifier in constraints.containerIdentifiers {
            // Verify we have a non-excluded entry for this key.
            switch assignments[identifier]?.binding {
            case .unversioned?, .version?, .revision?:
                continue
            case .excluded?, nil:
                return false
            }
        }

        return true
    }

    // MARK: Sequence Conformance

    // FIXME: This should really be a collection, but that takes significantly
    // more work given our current backing collection.

    typealias Iterator = AnyIterator<(PackageContainer, BoundVersion)>

    func makeIterator() -> Iterator {
        var it = assignments.makeIterator()
        return AnyIterator {
            if let (_, next) = it.next() {
                return (next.container, next.binding)
            } else {
                return nil
            }
        }
    }
}

func ==(lhs: VersionAssignmentSet, rhs: VersionAssignmentSet) -> Bool {
    if lhs.assignments.count != rhs.assignments.count { return false }
    for (container, lhsBinding) in lhs {
        switch rhs[container] {
        case let rhsBinding? where lhsBinding == rhsBinding:
            continue
        default:
            return false
        }
    }
    return true
}

/// A general purpose package dependency resolver.
///
/// This is a general purpose solver for the problem of:
///
/// Given an input list of constraints, where each constraint identifies a
/// container and version requirements, and, where each container supplies a
/// list of additional constraints ("dependencies") for an individual version,
/// then, choose an assignment of containers to versions such that:
///
/// 1. The assignment is complete: there exists an assignment for each container
/// listed in the union of the input constraint list and the dependency list for
/// every container in the assignment at the assigned version.
///
/// 2. The assignment is correct: the assigned version satisfies each constraint
/// referencing its matching container.
///
/// 3. The assignment is maximal: there is no other assignment satisfying #1 and
/// #2 such that all assigned version are greater than or equal to the versions
/// assigned in the result.
///
/// NOTE: It does not follow from #3 that this solver attempts to give an
/// "optimal" result. There may be many possible solutions satisfying #1, #2,
/// and #3, and optimality requires additional information (e.g. a
/// prioritization among packages).
///
/// As described, this problem is NP-complete (*). This solver currently
/// implements a basic depth-first greedy backtracking algorithm, and honoring
/// the order of dependencies as specified in the manifest file. The solver uses
/// persistent data structures to manage the accumulation of state along the
/// traversal, so the backtracking is not explicit, rather it is an implicit
/// side effect of the underlying copy-on-write data structures.
///
/// The resolver will always merge the complete set of immediate constraints for
/// a package (i.e., the version ranges of its immediate dependencies) into the
/// constraint set *before* traversing into any dependency. This property allows
/// packages to manually work around performance issues in the resolution
/// algorithm by _lifting_ problematic dependency constraints up to be immediate
/// dependencies.
///
/// There is currently no external control offered by the solver over _which_
/// solution satisfying the properties above is selected, if more than one are
/// possible. In practice, the algorithm is designed such that it will
/// effectively prefer (i.e., optimize for the newest version of) dependencies
/// which are earliest in the depth-first, pre-order, traversal.
///
/// (*) Via reduction from 3-SAT: Introduce a package for each variable, with
/// two versions representing true and false. For each clause `C_n`, introduce a
/// package `P(C_n)` representing the clause, with three versions; one for each
/// satisfying assignment of values to a literal with the corresponding precise
/// constraint on the input packages. Finally, construct an input constraint
/// list including a dependency on each clause package `P(C_n)` and an
/// open-ended version constraint. The given input is satisfiable iff the input
/// 3-SAT instance is.
public class DependencyResolver {
    public typealias Container = PackageContainer
    public typealias Binding = (container: PackageReference, binding: BoundVersion)

    /// The container provider used to load package containers.
    public let provider: PackageContainerProvider

    /// The resolver's delegate.
    public let delegate: DependencyResolverDelegate?

    /// Should resolver prefetch the containers.
    private let isPrefetchingEnabled: Bool

    /// Skip updating containers while fetching them.
    private let skipUpdate: Bool

    /// Lock used to get and set the error variable.
    private let errorLock: Lock = Lock()

    // FIXME: @testable private
    //
    /// Contains any error encountered during dependency resolution.
    var error: Swift.Error? {
        get {
            return errorLock.withLock { self.__error }
        } set {
            errorLock.withLock { self.__error = newValue }
        }
    }
    var __error: Swift.Error?

    /// Key used to cache a resolved subtree.
    private struct ResolveSubtreeCacheKey: Hashable {
        let container: Container
        let allConstraints: PackageContainerConstraintSet

        func hash(into hasher: inout Hasher) {
            hasher.combine(container.identifier)
            hasher.combine(allConstraints)
        }

        static func ==(lhs: ResolveSubtreeCacheKey, rhs: ResolveSubtreeCacheKey) -> Bool {
            return lhs.container.identifier == rhs.container.identifier && lhs.allConstraints == rhs.allConstraints
        }
    }

    /// Cache for subtree resolutions.
    private var _resolveSubtreeCache: [ResolveSubtreeCacheKey: AnySequence<VersionAssignmentSet>] = [:]
    
    /// Puts the resolver in incomplete mode.
    ///
    /// In this mode, no new containers will be requested from the provider.
    /// Instead, if a container is not already present in the resolver, it will
    /// skipped without raising an error. This is useful to avoid cloning
    /// repositories from network when trying to partially resolve the constraints.
    ///
    /// Note that the input constraints will always be fetched.
    public var isInIncompleteMode = false

    public init(
        _ provider: PackageContainerProvider,
        _ delegate: DependencyResolverDelegate? = nil,
        isPrefetchingEnabled: Bool = false,
        skipUpdate: Bool = false
    ) {
        self.provider = provider
        self.delegate = delegate
        self.isPrefetchingEnabled = isPrefetchingEnabled
        self.skipUpdate = skipUpdate
    }

    /// The dependency resolver result.
    public enum Result {
        /// A valid and complete assignment was found.
        case success([Binding])

        /// The dependency graph was unsatisfiable.
        ///
        /// The payload may contain conflicting constraints and pins.
        ///
        /// - parameters:
        ///     - dependencies: The package dependencies which make the graph unsatisfiable.
        ///     - pins: The pins which make the graph unsatisfiable.
        case unsatisfiable(dependencies: [PackageContainerConstraint], pins: [PackageContainerConstraint])

        /// The resolver encountered an error during resolution.
        case error(Swift.Error)
    }

    /// Cancel the dependency resolution operation.
    ///
    /// This method is thread-safe.
    public func cancel() {
        self.error = DependencyResolverError.cancelled
    }

    /// Execute the resolution algorithm to find a valid assignment of versions.
    ///
    /// If a valid assignment is not found, the resolver will go into incomplete
    /// mode and try to find the conflicting constraints.
    public func resolve(
        dependencies: [PackageContainerConstraint],
        pins: [PackageContainerConstraint]
    ) -> Result {
        do {
            // Reset the incomplete mode and run the resolver.
            self.isInIncompleteMode = false
            let constraints = dependencies
            return try .success(resolve(constraints: constraints, pins: pins))
        } catch DependencyResolverError.unsatisfiable {
            // FIXME: can we avoid this do..catch nesting?
            do {
                // If the result is unsatisfiable, try to debug.
                let debugger = ResolverDebugger(self)
                let badConstraints = try debugger.debug(dependencies: dependencies, pins: pins)
                return .unsatisfiable(dependencies: badConstraints.dependencies, pins: badConstraints.pins)
            } catch {
                return .error(error)
            }
        } catch {
            return .error(error)
        }
    }

    /// Execute the resolution algorithm to find a valid assignment of versions.
    ///
    /// - Parameters:
    ///   - constraints: The contraints to solve. It is legal to supply multiple
    ///                  constraints for the same container identifier.
    /// - Returns: A satisfying assignment of containers and their version binding.
    /// - Throws: DependencyResolverError, or errors from the underlying package provider.
    public func resolve(
        constraints: [PackageContainerConstraint],
        pins: [PackageContainerConstraint] = []
    ) throws -> [(container: PackageReference, binding: BoundVersion)] {
        return try resolveAssignment(constraints: constraints, pins: pins).map({ assignment in
            let (container, binding) = assignment
            let identifier = try self.isInIncompleteMode ? container.identifier : container.getUpdatedIdentifier(at: binding)
            // Get the updated identifier from the container.
            return (identifier, binding)
        })
    }

    /// Execute the resolution algorithm to find a valid assignment of versions.
    ///
    /// - Parameters:
    ///   - constraints: The contraints to solve. It is legal to supply multiple
    ///                  constraints for the same container identifier.
    /// - Returns: A satisfying assignment of containers and versions.
    /// - Throws: DependencyResolverError, or errors from the underlying package provider.
    func resolveAssignment(
        constraints: [PackageContainerConstraint],
        pins: [PackageContainerConstraint] = []
    ) throws -> VersionAssignmentSet {

        // Create a constraint set with the input pins.
        var allConstraints = PackageContainerConstraintSet()
        for constraint in pins {
            if let merged = allConstraints.merging(constraint) {
                allConstraints = merged
            } else {
                // FIXME: We should issue a warning if the pins can't be merged
                // for some reason.
            }
        }

        // Create an assignment for the input constraints.
        let mergedConstraints = merge(
            constraints: constraints,
            into: VersionAssignmentSet(),
            subjectTo: allConstraints,
            excluding: [:])

        // Prefetch the pins.
        if !isInIncompleteMode && isPrefetchingEnabled {
            prefetch(containers: pins.map({ $0.identifier }))
        }

        guard let assignment = mergedConstraints.first(where: { _ in true }) else {
            // Throw any error encountered during resolution.
            if let error = error {
                throw error
            }

            // Diagnose any missing versions for the constraints.
            try diagnoseMissingVersions(for: constraints)

            throw DependencyResolverError.unsatisfiable
        }

        return assignment
    }

    /// Diagnoses missing versions for the given constraints.
    private func diagnoseMissingVersions(for constraints: [RepositoryPackageConstraint]) throws {
        let constraintsWithNoAvailableVersions = constraints.filter { constraint in
            if case .versionSet(let versions) = constraint.requirement,
            let container = try? getContainer(for: constraint.identifier),
            // FIXME: This is hacky but we should be moving away from this resolver anyway.
            container._isRemoteContainer == true,
            !container.versions(filter: versions.contains).contains(where: { _ in true }) {
                return true
            }
            return false
        }

        if !constraintsWithNoAvailableVersions.isEmpty {
            throw DependencyResolverError.missingVersions(constraintsWithNoAvailableVersions)
        }
    }

    // FIXME: This needs to a way to return information on the failure, or we
    // will need to have it call the delegate directly.
    //
    // FIXME: @testable private
    //
    /// Resolve an individual container dependency tree.
    ///
    /// This is the primary method in our bottom-up algorithm for resolving
    /// dependencies. The inputs define an active set of constraints and set of
    /// versions to exclude (conceptually the latter could be merged with the
    /// former, but it is convenient to separate them in our
    /// implementation). The result is a sequence of all valid assignments for
    /// this container's subtree.
    ///
    /// - Parameters:
    ///   - container: The container to resolve.
    ///   - constraints: The external constraints which must be honored by the solution.
    ///   - exclusions: The list of individually excluded package versions.
    /// - Returns: A sequence of feasible solutions, starting with the most preferable.
    func resolveSubtree(
        _ container: Container,
        subjectTo allConstraints: PackageContainerConstraintSet,
        excluding allExclusions: [PackageReference: Set<Version>]
    ) -> AnySequence<VersionAssignmentSet> {
        guard self.error == nil else { return AnySequence([]) }

        // The key that is used to cache this assignement set.
        let cacheKey = ResolveSubtreeCacheKey(container: container, allConstraints: allConstraints)

        // Check if we have a cache hit for this subtree resolution.
        //
        // Note: We don't include allExclusions in the cache key so we ignore
        // the cache if its non-empty.
        //
        // FIXME: We can improve the cache miss rate here if we have a cached
        // entry with a broader constraint set. The cached sequence can be
        // filtered according to the new narrower constraint set.
        if allExclusions.isEmpty, let assignments = _resolveSubtreeCache[cacheKey] {
            return assignments
        }
        
        func validVersions(_ container: Container, in versionSet: VersionSetSpecifier) -> AnySequence<Version> {
            let exclusions = allExclusions[container.identifier] ?? Set()
            return AnySequence(container.versions(filter: {
                versionSet.contains($0) && !exclusions.contains($0)
            }))
        }

        // Helper method to abstract passing common parameters to merge().
        //
        // FIXME: We must detect recursion here.
        func merge(constraints: [PackageContainerConstraint], binding: BoundVersion) -> AnySequence<VersionAssignmentSet> {
            guard self.error == nil else { return AnySequence([]) }

            // Diagnose if this container depends on itself.
            if constraints.contains(where: { $0.identifier == container.identifier }) {
                error = DependencyResolverError.cycle(container.identifier)
                return AnySequence([])
            }

            // Create an assignment for the container.
            var assignment = VersionAssignmentSet()
            assignment[container] = binding

            return AnySequence(self.merge(
                constraints: constraints,
                into: assignment, subjectTo: allConstraints, excluding: allExclusions).lazy.map({ result in
                // We might not have a complete result in incomplete mode.
                if !self.isInIncompleteMode {
                    assert(result.checkIfValidAndComplete())
                }
                return result
            }))
        }

        var result: AnySequence<VersionAssignmentSet>
        switch allConstraints[container.identifier] {
        case .unversioned:
            guard let constraints = self.safely({ try container.getUnversionedDependencies() }) else {
                return AnySequence([])
            }
            // Merge the dependencies of unversioned constraint into the assignment.
            result = merge(constraints: constraints, binding: .unversioned)

        case .revision(let identifier):
            guard let constraints = self.safely({ try container.getDependencies(at: identifier) }) else {
                return AnySequence([])
            }

            // If we have any local packages, set the error and abort.
            //
            // We might want to support this in the future if the local package is contained
            // inside the dependency. That's going to be tricky though since we don't have
            // concrete checkouts yet.
            let incompatibleConstraints = constraints.filter{ $0.requirement == .unversioned }
            guard incompatibleConstraints.isEmpty else {
                self.error = DependencyResolverError.revisionDependencyContainsLocalPackage(
                    dependency: container.identifier.identity,
                    localPackage: incompatibleConstraints[0].identifier.identity
                )
                return AnySequence([])
            }

            result = merge(constraints: constraints, binding: .revision(identifier))

        case .versionSet(let versionSet):
            // The previous valid version that was picked.
            var previousVersion: Version? = nil

            // Attempt to select each valid version in the preferred order.
            result = AnySequence(validVersions(container, in: versionSet).lazy
                .flatMap({ version -> AnySequence<VersionAssignmentSet> in
                    assert(previousVersion != nil ? previousVersion! > version : true,
                           "container versions are improperly ordered")
                    previousVersion = version

                    // If we had encountered any error, return early.
                    guard self.error == nil else { return AnySequence([]) }

                    // Get the constraints for this container version and update the assignment to include each one.
                    // FIXME: Making these methods throwing will kill the lazy behavior.
                    guard var constraints = self.safely({ try container.getDependencies(at: version) }) else {
                        return AnySequence([])
                    }

                    // Since we don't want to request additional containers in incomplete
                    // mode, remove any dependency that we don't already have.
                    if self.isInIncompleteMode {
                        constraints = constraints.filter({ self.containers[$0.identifier] != nil })
                    }

                    // Since this is a versioned container, none of its
                    // dependencies can have a revision constraints.
                    let incompatibleConstraints: [(PackageReference, String)]
                    incompatibleConstraints = constraints.compactMap({
                        switch $0.requirement {
                        case .versionSet:
                            return nil
                        case .revision(let revision):
                            return ($0.identifier, revision)
                        case .unversioned:
                            // FIXME: Maybe we should have metadata inside unversion to signify
                            // if its a local or edited dependency. We add edited constraints
                            // as inputs so it shouldn't really matter because an edited
                            // requirement can't be specified in the manifest file.
                            return ($0.identifier, "local")
                        }
                    })
                    // If we have any revision constraints, set the error and abort.
                    guard incompatibleConstraints.isEmpty else {
                        self.error = DependencyResolverError.incompatibleConstraints(
                            dependency: (container.identifier, version.description),
                            revisions: incompatibleConstraints)
                        return AnySequence([])
                    }

                    return merge(constraints: constraints, binding: .version(version))
                }))
        }

        if allExclusions.isEmpty {
            // Ensure we can cache this sequence.
            result = AnySequence(CacheableSequence(result))
            _resolveSubtreeCache[cacheKey] = result
        }
        return result
    }

    /// Find all solutions for `constraints` with the results merged into the `assignment`.
    ///
    /// - Parameters:
    ///   - constraints: The input list of constraints to solve.
    ///   - assignment: The assignment to merge the result into.
    ///   - allConstraints: An additional set of constraints on the viable solutions.
    ///   - allExclusions: A set of package assignments to exclude from consideration.
    /// - Returns: A sequence of all valid satisfying assignment, in order of preference.
    private func merge(
        constraints: [PackageContainerConstraint],
        into assignment: VersionAssignmentSet,
        subjectTo allConstraints: PackageContainerConstraintSet,
        excluding allExclusions: [PackageReference: Set<Version>]
    ) -> AnySequence<VersionAssignmentSet> {
        guard self.error == nil else { return AnySequence([]) }

        var allConstraints = allConstraints

        // Never prefetch when running in incomplete mode.
        if !isInIncompleteMode && isPrefetchingEnabled {
            prefetch(containers: constraints.map({ $0.identifier }))
        }

        // Update the active constraint set to include all active constraints.
        //
        // We want to put all of these constraints in up front so that we are
        // more likely to get back a viable solution.
        //
        // FIXME: We should have a test for this, probably by adding some kind
        // of statistics on the number of backtracks.
        for constraint in constraints {
            guard let merged = allConstraints.merging(constraint) else {
                return AnySequence([])
            }
            allConstraints = merged
        }

        // Perform an (eager) reduction merging each container into the (lazy)
        // sequence of possible assignments.
        //
        // NOTE: What we are *accumulating* here is a lazy sequence (of
        // solutions) satisfying some number of the constraints; the final lazy
        // sequence is effectively one which has all of the constraints
        // merged. Thus, the reduce itself can be eager since the result is
        // lazy.
        return AnySequence(constraints
            .map({ $0.identifier })
            .reduce(AnySequence([(assignment, allConstraints)]), {
                (possibleAssignments, identifier) -> AnySequence<(VersionAssignmentSet, PackageContainerConstraintSet)> in
                // If we had encountered any error, return early.
                guard self.error == nil else { return AnySequence([]) }

                // Get the container.
                //
                // Failures here will immediately abort the solution, although in
                // theory one could imagine attempting to find a solution not
                // requiring this container. It isn't clear that is something we
                // would ever want to handle at this level.
                //
                // FIXME: Making these methods throwing will kill the lazy behavior,
                guard let container = safely({ try getContainer(for: identifier) }) else {
                    return AnySequence([])
                }

                // Return a new lazy sequence merging all possible subtree solutions into all possible incoming
                //  assignments.
                return AnySequence(possibleAssignments.lazy.flatMap({ value -> AnySequence<(VersionAssignmentSet, PackageContainerConstraintSet)> in
                    let (assignment, allConstraints) = value
                    let subtree = self.resolveSubtree(container, subjectTo: allConstraints, excluding: allExclusions)
                    return AnySequence(subtree.lazy.compactMap({ subtreeAssignment -> (VersionAssignmentSet, PackageContainerConstraintSet)? in
                            // We found a valid subtree assignment, attempt to merge it with the
                            // current solution.
                            guard let newAssignment = assignment.merging(subtreeAssignment) else {
                                // The assignment couldn't be merged with the current
                                // assignment, or the constraint sets couldn't be merged.
                                //
                                // This happens when (a) the subtree has a package overlapping
                                // with a previous subtree assignment, and (b) the subtrees
                                // needed to resolve different versions due to constraints not
                                // present in the top-down constraint set.
                                return nil
                            }

                            // Update the working assignment and constraint set.
                            //
                            // This should always be feasible, because all prior constraints
                            // were part of the input constraint request (see comment around
                            // initial `merge` outside the loop).
                            guard let merged = allConstraints.merging(subtreeAssignment.constraints) else {
                                preconditionFailure("unsatisfiable constraints while merging subtree")
                            }

                            // We found a valid assignment and updated constraint set.
                            return (newAssignment, merged)
                        }))
                }))
            })
            .lazy
            .map({ $0.0 }))
    }

    /// Executes the body and return the value if the body doesn't throw.
    /// Returns nil if the body throws and save the error.
    private func safely<T>(_ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            self.error = error
        }
        return nil
    }

    // MARK: Container Management

    /// Condition for container management structures.
    private let fetchCondition = Condition()

    /// The active set of managed containers.
    public var containers: [PackageReference: Container] {
        return fetchCondition.whileLocked({
            _fetchedContainers.spm_flatMapValues({
                try? $0.dematerialize()
            })
        })
    }

    /// The list of fetched containers.
    private var _fetchedContainers: [PackageReference: Basic.Result<Container, AnyError>] = [:]

    /// The set of containers requested so far.
    private var _prefetchingContainers: Set<PackageReference> = []

    /// Get the container for the given identifier, loading it if necessary.
    fileprivate func getContainer(for identifier: PackageReference) throws -> Container {
        return try fetchCondition.whileLocked {
            // Return the cached container, if available.
            if let container = _fetchedContainers[identifier] {
                return try container.dematerialize()
            }

            // If this container is being prefetched, wait for that to complete.
            while _prefetchingContainers.contains(identifier) {
                fetchCondition.wait()
            }

            // The container may now be available in our cache if it was prefetched.
            if let container = _fetchedContainers[identifier] {
                return try container.dematerialize()
            }

            // Otherwise, fetch the container synchronously.
            let container = try await { provider.getContainer(for: identifier, skipUpdate: skipUpdate, completion: $0) }
            self._fetchedContainers[identifier] = Basic.Result(container)
            return container
        }
    }

    /// Starts prefetching the given containers.
    private func prefetch(containers identifiers: [PackageReference]) {
        fetchCondition.whileLocked {
            // Process each container.
            for identifier in identifiers {
                // Skip if we're already have this container or are pre-fetching it.
                guard _fetchedContainers[identifier] == nil,
                      !_prefetchingContainers.contains(identifier) else {
                    continue
                }

                // Otherwise, record that we're prefetching this container.
                _prefetchingContainers.insert(identifier)

                provider.getContainer(for: identifier, skipUpdate: skipUpdate) { container in
                    self.fetchCondition.whileLocked {
                        // Update the structures and signal any thread waiting
                        // on prefetching to finish.
                        self._fetchedContainers[identifier] = container
                        self._prefetchingContainers.remove(identifier)
                        self.fetchCondition.signal()
                    }
                }
            }
        }
    }
}

/// The resolver debugger.
///
/// Finds the constraints which results in graph being unresolvable.
private struct ResolverDebugger {

    enum Error: Swift.Error {
        /// Reached the time limit without completing the algorithm.
        case reachedTimeLimit
    }

    /// Reference to the resolver.
    unowned let resolver: DependencyResolver

    /// Create a new debugger.
    init(_ resolver: DependencyResolver) {
        self.resolver = resolver
    }

    /// The time limit in seconds after which we abort finding a solution.
    let timeLimit = 10.0

    /// Returns the constraints which should be removed in order to make the
    /// graph resolvable.
    ///
    /// We use delta debugging algoritm to find the smallest set of constraints
    /// which can be removed from the input in order to make the graph
    /// satisfiable.
    ///
    /// This algorithm can be exponential, so we abort after the predefined time limit.
    func debug(
        dependencies inputDependencies: [PackageContainerConstraint],
        pins inputPins: [PackageContainerConstraint]
    ) throws -> (dependencies: [PackageContainerConstraint], pins: [PackageContainerConstraint]) {

        // Form the dependencies array.
        //
		// We iterate over the inputs and fetch all the dependencies for
		// unversioned requirements as the unversioned requirements are not
		// relevant to the dependency resolution.
        var dependencies = [PackageContainerConstraint]()
        for constraint in inputDependencies {
            if constraint.requirement == .unversioned {
                // Ignore the errors here.
                do {
                    let container = try resolver.getContainer(for: constraint.identifier)
                    dependencies += try container.getUnversionedDependencies()
                } catch {}
            } else {
                dependencies.append(constraint)
            }
        }

        // Form a set of all unversioned dependencies.
        let unversionedDependencies = Set(inputDependencies.filter({ $0.requirement == .unversioned }).map({ $0.identifier }))

        // Remove the unversioned constraints from dependencies and pins.
        dependencies = dependencies.filter({ !unversionedDependencies.contains($0.identifier) })
        let pins = inputPins.filter({ !unversionedDependencies.contains($0.identifier) })

        // Put the resolver in incomplete mode to avoid cloning new repositories.
        resolver.isInIncompleteMode = true

        let deltaAlgo = DeltaAlgorithm<ResolverChange>()
        let allPackages = Set(dependencies.map({ $0.identifier }))

        // Compute the set of changes.
        let allChanges: Set<ResolverChange> = {
            var set = Set<ResolverChange>()
            set.formUnion(dependencies.map({ ResolverChange.allowPackage($0.identifier) }))
            set.formUnion(pins.map({ ResolverChange.allowPin($0.identifier) }))
            return set
        }()

        // Compute the current time.
        let startTime = NSDate().timeIntervalSince1970
        var timeLimitReached = false

        // Run the delta debugging algorithm.
        let badChanges = try deltaAlgo.run(changes: allChanges) { changes in
            // Check if we reached the time limits.
            timeLimitReached = timeLimitReached || (NSDate().timeIntervalSince1970 - startTime) >= timeLimit
            // If we reached the time limit, throw.
            if timeLimitReached {
                throw Error.reachedTimeLimit
            }

            // Find the set of changes we want to allow in this predicate.
            let allowedChanges = allChanges.subtracting(changes)

            // Find the packages which are allowed and disallowed to participate
            // in this changeset.
            let allowedPackages = Set(allowedChanges.compactMap({ $0.allowedPackage }))
            let disallowedPackages = allPackages.subtracting(allowedPackages)

            // Start creating constraints.
            //
            // First, add all the package dependencies.
            var constraints = dependencies

            // Set all disallowed packages to unversioned, so they stay out of resolution.
            constraints += disallowedPackages.map({
                PackageContainerConstraint(container: $0, requirement: .unversioned)
            })

            let allowedPins = Set(allowedChanges.compactMap({ $0.allowedPin }))

            // It is always a failure if this changeset contains a pin of
            // a disallowed package.
            if allowedPins.first(where: disallowedPackages.contains) != nil {
                return false
            }

            // Finally, add the allowed pins.
            constraints += pins.filter({ allowedPins.contains($0.identifier) })

            return try satisfies(constraints)
        }

        // Filter the input with found result and return.
        let badDependencies = Set(badChanges.compactMap({ $0.allowedPackage }))
        let badPins = Set(badChanges.compactMap({ $0.allowedPin }))
        return (
            dependencies: dependencies.filter({ badDependencies.contains($0.identifier) }),
            pins: pins.filter({ badPins.contains($0.identifier) })
        )
    }

    /// Returns true if the constraints are satisfiable.
    func satisfies(_ constraints: [PackageContainerConstraint]) throws -> Bool {
        do {
            _ = try resolver.resolve(constraints: constraints, pins: [])
            return true
        } catch DependencyResolverError.unsatisfiable {
            return false
        }
    }

    /// Represents a single change which should introduced during delta debugging.
    enum ResolverChange: Hashable {

        /// Allow the package with the given identifier.
        case allowPackage(PackageReference)

        /// Allow the pins with the given identifier.
        case allowPin(PackageReference)

        /// Returns the allowed pin identifier.
        var allowedPin: PackageReference? {
            if case let .allowPin(identifier) = self {
                return identifier
            }
            return nil
        }

        // Returns the allowed package identifier.
        var allowedPackage: PackageReference? {
            if case let .allowPackage(identifier) = self {
                return identifier
            }
            return nil
        }
    }
}
