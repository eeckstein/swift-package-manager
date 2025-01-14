#if !canImport(ObjectiveC)
import XCTest

extension DependencyResolverTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__DependencyResolverTests = [
        ("testBasics", testBasics),
        ("testCompleteness", testCompleteness),
        ("testContainerConstraintSet", testContainerConstraintSet),
        ("testCycle", testCycle),
        ("testDiagnostics", testDiagnostics),
        ("testExactConstraint", testExactConstraint),
        ("testIncompleteMode", testIncompleteMode),
        ("testLazyResolve", testLazyResolve),
        ("testPrereleaseResolve", testPrereleaseResolve),
        ("testResolve", testResolve),
        ("testResolveSubtree", testResolveSubtree),
        ("testRevisionConstraint2", testRevisionConstraint2),
        ("testRevisionConstraint", testRevisionConstraint),
        ("testUnversionedConstraint", testUnversionedConstraint),
        ("testVersionAssignment", testVersionAssignment),
        ("testVersionSetSpecifier", testVersionSetSpecifier),
    ]
}

extension PackageGraphTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__PackageGraphTests = [
        ("testBasic", testBasic),
        ("testCycle2", testCycle2),
        ("testCycle", testCycle),
        ("testDuplicateInterPackageTargetNames", testDuplicateInterPackageTargetNames),
        ("testDuplicateModules", testDuplicateModules),
        ("testDuplicateProducts", testDuplicateProducts),
        ("testEmptyDependency", testEmptyDependency),
        ("testMultipleDuplicateModules", testMultipleDuplicateModules),
        ("testNestedDuplicateModules", testNestedDuplicateModules),
        ("testProductDependencies", testProductDependencies),
        ("testProductDependencyNotFound", testProductDependencyNotFound),
        ("testSeveralDuplicateModules", testSeveralDuplicateModules),
        ("testTestTargetDeclInExternalPackage", testTestTargetDeclInExternalPackage),
        ("testUnsafeFlags", testUnsafeFlags),
        ("testUnusedDependency2", testUnusedDependency2),
        ("testUnusedDependency", testUnusedDependency),
    ]
}

extension PubgrubTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__PubgrubTests = [
        ("testBranchBasedPackageCycle", testBranchBasedPackageCycle),
        ("testBranchedBasedPin", testBranchedBasedPin),
        ("testBranchOverriding3", testBranchOverriding3),
        ("testBranchOverriding4", testBranchOverriding4),
        ("testConflict1", testConflict1),
        ("testConflict2", testConflict2),
        ("testConflict3", testConflict3),
        ("testCycle1", testCycle1),
        ("testCycle2", testCycle2),
        ("testIncompatibilityNormalizeTermsOnInit", testIncompatibilityNormalizeTermsOnInit),
        ("testIncompatibleToolsVersion1", testIncompatibleToolsVersion1),
        ("testIncompatibleToolsVersion2", testIncompatibleToolsVersion2),
        ("testIncompatibleToolsVersion3", testIncompatibleToolsVersion3),
        ("testIncompatibleToolsVersion4", testIncompatibleToolsVersion4),
        ("testIncompatibleToolsVersion5", testIncompatibleToolsVersion5),
        ("testLocalPackageCycle", testLocalPackageCycle),
        ("testMissingVersion", testMissingVersion),
        ("testNonExistentPackage", testNonExistentPackage),
        ("testNonVersionDependencyInVersionDependency1", testNonVersionDependencyInVersionDependency1),
        ("testNonVersionDependencyInVersionDependency2", testNonVersionDependencyInVersionDependency2),
        ("testNonVersionDependencyInVersionDependency3", testNonVersionDependencyInVersionDependency3),
        ("testPartialPins", testPartialPins),
        ("testPositiveTerms", testPositiveTerms),
        ("testResolutionAvoidingConflictResolutionDuringDecisionMaking", testResolutionAvoidingConflictResolutionDuringDecisionMaking),
        ("testResolutionBranchingErrorReporting", testResolutionBranchingErrorReporting),
        ("testResolutionConflictResolutionWithAPartialSatisfier", testResolutionConflictResolutionWithAPartialSatisfier),
        ("testResolutionLinearErrorReporting", testResolutionLinearErrorReporting),
        ("testResolutionNoConflicts", testResolutionNoConflicts),
        ("testResolutionNonExistentVersion", testResolutionNonExistentVersion),
        ("testResolutionPerformingConflictResolution", testResolutionPerformingConflictResolution),
        ("testResolutionWithOverridingBranchBasedDependency", testResolutionWithOverridingBranchBasedDependency),
        ("testResolutionWithOverridingBranchBasedDependency2", testResolutionWithOverridingBranchBasedDependency2),
        ("testResolutionWithOverridingBranchBasedDependency3", testResolutionWithOverridingBranchBasedDependency3),
        ("testResolutionWithOverridingBranchBasedDependency4", testResolutionWithOverridingBranchBasedDependency4),
        ("testResolutionWithRevisionConflict", testResolutionWithRevisionConflict),
        ("testResolutionWithSimpleBranchBasedDependency", testResolutionWithSimpleBranchBasedDependency),
        ("testResolutionWithSimpleBranchBasedDependency2", testResolutionWithSimpleBranchBasedDependency2),
        ("testResolutionWithUnavailableRevision", testResolutionWithUnavailableRevision),
        ("testResolverAddIncompatibility", testResolverAddIncompatibility),
        ("testResolverConflictResolution", testResolverConflictResolution),
        ("testResolverDecisionMaking", testResolverDecisionMaking),
        ("testResolverUnitPropagation", testResolverUnitPropagation),
        ("testSolutionAddAssignments", testSolutionAddAssignments),
        ("testSolutionBacktrack", testSolutionBacktrack),
        ("testSolutionFindSatisfiers", testSolutionFindSatisfiers),
        ("testSolutionPositive", testSolutionPositive),
        ("testSolutionUndecided", testSolutionUndecided),
        ("testTermInverse", testTermInverse),
        ("testTermIsValidDecision", testTermIsValidDecision),
        ("testTermRelation", testTermRelation),
        ("testTermSatisfies", testTermSatisfies),
        ("testTrivialPinStore", testTrivialPinStore),
        ("testUnversioned1", testUnversioned1),
        ("testUnversioned2", testUnversioned2),
        ("testUnversioned3", testUnversioned3),
        ("testUnversioned4", testUnversioned4),
        ("testUnversioned5", testUnversioned5),
        ("testUnversioned6", testUnversioned6),
        ("testUnversioned7", testUnversioned7),
        ("testUnversioned8", testUnversioned8),
        ("testUnversioned9", testUnversioned9),
        ("testUpdatePackageIdentifierAfterResolution", testUpdatePackageIdentifierAfterResolution),
    ]
}

extension RepositoryPackageContainerProviderTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__RepositoryPackageContainerProviderTests = [
        ("testBasics", testBasics),
        ("testPackageReference", testPackageReference),
        ("testPrereleaseVersions", testPrereleaseVersions),
        ("testSimultaneousVersions", testSimultaneousVersions),
        ("testVersions", testVersions),
        ("testVprefixVersions", testVprefixVersions),
    ]
}

extension VersionSetSpecifierTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__VersionSetSpecifierTests = [
        ("testDifference", testDifference),
        ("testIntersection", testIntersection),
        ("testUnion", testUnion),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DependencyResolverTests.__allTests__DependencyResolverTests),
        testCase(PackageGraphTests.__allTests__PackageGraphTests),
        testCase(PubgrubTests.__allTests__PubgrubTests),
        testCase(RepositoryPackageContainerProviderTests.__allTests__RepositoryPackageContainerProviderTests),
        testCase(VersionSetSpecifierTests.__allTests__VersionSetSpecifierTests),
    ]
}
#endif
