/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageLoading
import PackageModel
@testable import PackageGraph
import SourceControl

import TestSupport

private class MockRepository: Repository {
    /// The fake URL of the repository.
    let url: String

    /// The known repository versions, as a map of tags to manifests.
    let versions: [Version: Manifest]

    let fs: FileSystem

    init(fs: FileSystem, url: String, versions: [Version: Manifest]) {
        self.fs = fs
        self.url = url
        self.versions = versions
    }

    var specifier: RepositorySpecifier {
        return RepositorySpecifier(url: url)
    }

    var packageRef: PackageReference {
        return PackageReference(identity: url.lowercased(), path: url)
    }

    var tags: [String] {
        return versions.keys.map{ String(describing: $0) }
    }

    func resolveRevision(tag: String) throws -> Revision {
        assert(versions.index(forKey: Version(string: tag)!) != nil)
        return Revision(identifier: tag)
    }

    func resolveRevision(identifier: String) throws -> Revision {
        fatalError("Unexpected API call")
    }

    func fetch() throws {
        fatalError("Unexpected API call")
    }

    func exists(revision: Revision) -> Bool {
        fatalError("Unexpected API call")
    }

    func remove() throws {
        fatalError("Unexpected API call")
    }

    func openFileView(revision: Revision) throws -> FileSystem {
        assert(versions.index(forKey: Version(string: revision.identifier)!) != nil)
        // This is used for reading the tools version.
        return fs
    }
}

private class MockRepositories: RepositoryProvider {
    /// The known repositories, as a map of URL to repository.
    let repositories: [String: MockRepository]

    /// A mock manifest loader for all repositories.
    let manifestLoader: MockManifestLoader

    init(repositories repositoryList: [MockRepository]) {
        var allManifests: [MockManifestLoader.Key: Manifest] = [:]
        var repositories: [String: MockRepository] = [:]
        for repository in repositoryList {
            assert(repositories.index(forKey: repository.url) == nil)
            repositories[repository.url] = repository
            for (version, manifest) in repository.versions {
                allManifests[MockManifestLoader.Key(url: repository.url, version: version)] = manifest
            }
        }

        self.repositories = repositories
        self.manifestLoader = MockManifestLoader(manifests: allManifests)
    }

    func fetch(repository: RepositorySpecifier, to path: AbsolutePath) throws {
        // No-op.
        assert(repositories.index(forKey: repository.url) != nil)
    }

    func checkoutExists(at path: AbsolutePath) throws -> Bool {
        return false
    }

    func open(repository: RepositorySpecifier, at path: AbsolutePath) throws -> Repository {
        return repositories[repository.url]!
    }

    func cloneCheckout(repository: RepositorySpecifier, at sourcePath: AbsolutePath, to destinationPath: AbsolutePath, editable: Bool) throws {
        fatalError("unexpected API call")
    }

    func openCheckout(at path: AbsolutePath) throws -> WorkingCheckout {
        fatalError("unexpected API call")
    }
}

private class MockResolverDelegate: DependencyResolverDelegate, RepositoryManagerDelegate {
    typealias Identifier = RepositoryPackageContainer.Identifier

    var fetched = [RepositorySpecifier]()

    func fetchingWillBegin(handle: RepositoryManager.RepositoryHandle) {
        fetched += [handle.repository]
    }

    func fetchingDidFinish(handle: RepositoryManager.RepositoryHandle, error: Swift.Error?) {
    }
}

private struct MockDependencyResolver {
    let tmpDir: TemporaryDirectory
    let repositories: MockRepositories
    let delegate: MockResolverDelegate
    private let resolver: DependencyResolver

    init(repositories: MockRepository...) {
        self.tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        self.repositories = MockRepositories(repositories: repositories)
        self.delegate = MockResolverDelegate()
        let repositoryManager = RepositoryManager(path: self.tmpDir.path, provider: self.repositories, delegate: self.delegate)
        let provider = RepositoryPackageContainerProvider(
            repositoryManager: repositoryManager, manifestLoader: self.repositories.manifestLoader)
        self.resolver = DependencyResolver(provider, delegate)
    }

    func resolve(constraints: [RepositoryPackageConstraint]) throws -> [(container: PackageReference, binding: BoundVersion)] {
        return try resolver.resolve(constraints: constraints)
    }
}

// Some handy versions & ranges.
//
// The convention is that the name matches how specific the version is, so "v1"
// means "any 1.?.?", and "v1_1" means "any 1.1.?".

private let v1: Version = "1.0.0"
private let v2: Version = "2.0.0"
private let v1Range: VersionSetSpecifier = .range("1.0.0" ..< "2.0.0")

class RepositoryPackageContainerProviderTests: XCTestCase {

    func testPackageReference() {
        func assertIdentity(_ url: String, _ identity: String, file: StaticString = #file, line: UInt = #line) {
            let computedIdentity = PackageReference.computeIdentity(packageURL: url)
            XCTAssertEqual(computedIdentity, identity, file: file, line: line)
        }
        assertIdentity("foo", "foo")
        assertIdentity("/foo", "foo")
        assertIdentity("/foo/bar", "bar")
        assertIdentity("foo/bar", "bar")
        assertIdentity("https://foo/bar/baz", "baz")
        assertIdentity("git@github.com/foo/bar/baz", "baz")
        assertIdentity("/path/to/foo/bar/baz/", "baz")
        assertIdentity("https://foo/bar/baz.git", "baz")
        assertIdentity("git@github.com/foo/bar/baz.git", "baz")
        assertIdentity("/path/to/foo/bar/baz.git", "baz")
    }

    func testBasics() throws {
        let fs = InMemoryFileSystem()
        try fs.writeFileContents(AbsolutePath("/Package.swift"), bytes: ByteString(encodingAsUTF8: "// swift-tools-version:\(ToolsVersion.currentToolsVersion)\n"))
        let repoA = MockRepository(
            fs: fs,
            url: "A",
            versions: [
                v1: Manifest(
                    name: "Foo",
                    platforms: [],
                    path: AbsolutePath("/Package.swift"),
                    url: "A",
                    version: v1,
                    manifestVersion: .v4,
                    dependencies: [PackageDependencyDescription(url: "B", requirement: .upToNextMajor(from: "2.0.0"))]
                )
            ])
        let repoB = MockRepository(
            fs: fs,
            url: "B",
            versions: [
                v2: Manifest(
                    name: "Bar",
                    platforms: [],
                    path: AbsolutePath("/Package.swift"),
                    url: "B",
                    version: v2,
                    manifestVersion: .v4
                )
            ])
        let resolver = MockDependencyResolver(repositories: repoA, repoB)

        let constraints = [
            RepositoryPackageConstraint(
                container: repoA.packageRef,
                versionRequirement: v1Range)
        ]
        let result: [(PackageReference, Version)] = try resolver.resolve(constraints: constraints).compactMap {
            guard case .version(let version) = $0.binding else {
                XCTFail("Unexpecting non version binding \($0.binding)")
                return nil
            }
            return ($0.container, version)
        }
        XCTAssertEqual(result, [
                repoA.packageRef: v1,
                repoB.packageRef: v2,
            ])
        XCTAssertEqual(resolver.delegate.fetched, [repoA.specifier, repoB.specifier])
    }

    func testVprefixVersions() throws {
        let fs = InMemoryFileSystem()

        let repoPath = AbsolutePath.root.appending(component: "some-repo")
        let filePath = repoPath.appending(component: "Package.swift")

        let specifier = RepositorySpecifier(url: repoPath.pathString)
        let repo = InMemoryGitRepository(path: repoPath, fs: fs)
        try repo.createDirectory(repoPath, recursive: true)
        try repo.writeFileContents(filePath, bytes: ByteString(encodingAsUTF8: "// swift-tools-version:\(ToolsVersion.currentToolsVersion)\n"))
        repo.commit()
        try repo.tag(name: "v1.0.0")
        try repo.tag(name: "v1.0.1")
        try repo.tag(name: "v1.0.2")
        try repo.tag(name: "v1.0.3")
        try repo.tag(name: "v2.0.3")

        let inMemRepoProvider = InMemoryGitRepositoryProvider()
        inMemRepoProvider.add(specifier: specifier, repository: repo)

        let p = AbsolutePath.root.appending(component: "repoManager")
        try fs.createDirectory(p, recursive: true)
        let repositoryManager = RepositoryManager(
            path: p,
            provider: inMemRepoProvider,
            delegate: MockResolverDelegate(),
            fileSystem: fs)

        let provider = RepositoryPackageContainerProvider(
                repositoryManager: repositoryManager,
                manifestLoader: MockManifestLoader(manifests: [:]))
        let ref = PackageReference(identity: "foo", path: repoPath.pathString)
        let container = try await { provider.getContainer(for: ref, completion: $0) }
        let v = container.versions(filter: { _ in true }).map{$0}
        XCTAssertEqual(v, ["2.0.3", "1.0.3", "1.0.2", "1.0.1", "1.0.0"])
    }

    func testVersions() throws {
        let fs = InMemoryFileSystem()

        let repoPath = AbsolutePath.root.appending(component: "some-repo")
        let filePath = repoPath.appending(component: "Package.swift")

        let specifier = RepositorySpecifier(url: repoPath.pathString)
        let repo = InMemoryGitRepository(path: repoPath, fs: fs)

        try repo.createDirectory(repoPath, recursive: true)

        try repo.writeFileContents(filePath, bytes: "// swift-tools-version:3.1")
        repo.commit()
        try repo.tag(name: "1.0.0")

        try repo.writeFileContents(filePath, bytes: "// swift-tools-version:4.0")
        repo.commit()
        try repo.tag(name: "1.0.1")

        try repo.writeFileContents(filePath, bytes: "// swift-tools-version:4.2.0;hello\n")
        repo.commit()
        try repo.tag(name: "1.0.2")

        try repo.writeFileContents(filePath, bytes: "// swift-tools-version:4.2.0\n")
        repo.commit()
        try repo.tag(name: "1.0.3")

        let inMemRepoProvider = InMemoryGitRepositoryProvider()
        inMemRepoProvider.add(specifier: specifier, repository: repo)

        let p = AbsolutePath.root.appending(component: "repoManager")
        try fs.createDirectory(p, recursive: true)
        let repositoryManager = RepositoryManager(
            path: p,
            provider: inMemRepoProvider,
            delegate: MockResolverDelegate(),
            fileSystem: fs)

        func createProvider(_ currentToolsVersion: ToolsVersion) -> RepositoryPackageContainerProvider {
            return RepositoryPackageContainerProvider(
                repositoryManager: repositoryManager,
                manifestLoader: MockManifestLoader(manifests: [:]),
                currentToolsVersion: currentToolsVersion)
        }

        do {
            let provider = createProvider(ToolsVersion(version: "4.0.0"))
            let ref = PackageReference(identity: "foo", path: specifier.url)
            let container = try await { provider.getContainer(for: ref, completion: $0) }
            let v = container.versions(filter: { _ in true }).map{$0}
            XCTAssertEqual(v, ["1.0.1"])
        }

        do {
            let provider = createProvider(ToolsVersion(version: "4.2.0"))
            let ref = PackageReference(identity: "foo", path: specifier.url)
            let container = try await { provider.getContainer(for: ref, completion: $0) }
            XCTAssertEqual((container as! RepositoryPackageContainer).validToolsVersionsCache, [:])
            let v = container.versions(filter: { _ in true }).map{$0}
            XCTAssertEqual((container as! RepositoryPackageContainer).validToolsVersionsCache, ["1.0.1": true, "1.0.0": false, "1.0.3": true, "1.0.2": true])
            XCTAssertEqual(v, ["1.0.3", "1.0.2", "1.0.1"])
        }

        do {
            let provider = createProvider(ToolsVersion(version: "3.0.0"))
            let ref = PackageReference(identity: "foo", path: specifier.url)
            let container = try await { provider.getContainer(for: ref, completion: $0) }
            let v = container.versions(filter: { _ in true }).map{$0}
            XCTAssertEqual(v, [])
        }

        // Test that getting dependencies on a revision that has unsupported tools version is diganosed properly.
        do {
            let provider = createProvider(ToolsVersion(version: "4.0.0"))
            let ref = PackageReference(identity: "foo", path: specifier.url)
            let container = try await { provider.getContainer(for: ref, completion: $0) } as! RepositoryPackageContainer
            let revision = try container.getRevision(forTag: "1.0.0")
            do {
                _ = try container.getDependencies(at: revision.identifier)
            } catch let error as RepositoryPackageContainer.GetDependenciesErrorWrapper {
                let error = error.underlyingError as! UnsupportedToolsVersion
                XCTAssertMatch(error.description, .and(.prefix("package at '/some-repo' @"), .suffix("is using Swift tools version 3.1.0 which is no longer supported; consider using '// swift-tools-version:4.0' to specify the current tools version")))
            }
        }
    }

    func testPrereleaseVersions() throws {
        let fs = InMemoryFileSystem()

        let repoPath = AbsolutePath.root.appending(component: "some-repo")
        let filePath = repoPath.appending(component: "Package.swift")

        let specifier = RepositorySpecifier(url: repoPath.pathString)
        let repo = InMemoryGitRepository(path: repoPath, fs: fs)
        try repo.createDirectory(repoPath, recursive: true)
        try repo.writeFileContents(filePath, bytes: ByteString(encodingAsUTF8: "// swift-tools-version:\(ToolsVersion.currentToolsVersion)\n"))
        repo.commit()
        try repo.tag(name: "1.0.0-alpha.1")
        try repo.tag(name: "1.0.0-beta.1")
        try repo.tag(name: "1.0.0")
        try repo.tag(name: "1.0.1")
        try repo.tag(name: "1.0.2-dev")
        try repo.tag(name: "1.0.2-dev.2")
        try repo.tag(name: "1.0.4-alpha")

        let inMemRepoProvider = InMemoryGitRepositoryProvider()
        inMemRepoProvider.add(specifier: specifier, repository: repo)

        let p = AbsolutePath.root.appending(component: "repoManager")
        try fs.createDirectory(p, recursive: true)
        let repositoryManager = RepositoryManager(
            path: p,
            provider: inMemRepoProvider,
            delegate: MockResolverDelegate(),
            fileSystem: fs)

        let provider = RepositoryPackageContainerProvider(
            repositoryManager: repositoryManager,
            manifestLoader: MockManifestLoader(manifests: [:]))
        let ref = PackageReference(identity: "foo", path: repoPath.pathString)
        let container = try await { provider.getContainer(for: ref, completion: $0) }
        let v = container.versions(filter: { _ in true }).map{$0}
        XCTAssertEqual(v, ["1.0.4-alpha", "1.0.2-dev.2", "1.0.2-dev", "1.0.1", "1.0.0", "1.0.0-beta.1", "1.0.0-alpha.1"])
    }

    func testSimultaneousVersions() throws {
        let fs = InMemoryFileSystem()

        let repoPath = AbsolutePath.root.appending(component: "some-repo")
        let filePath = repoPath.appending(component: "Package.swift")

        let specifier = RepositorySpecifier(url: repoPath.pathString)
        let repo = InMemoryGitRepository(path: repoPath, fs: fs)
        try repo.createDirectory(repoPath, recursive: true)
        try repo.writeFileContents(filePath, bytes: ByteString(encodingAsUTF8: "// swift-tools-version:\(ToolsVersion.currentToolsVersion)\n"))
        repo.commit()
        try repo.tag(name: "v1.0.0")
        try repo.tag(name: "1.0.0")
        try repo.tag(name: "1.0.1")
        try repo.tag(name: "v1.0.2")
        try repo.tag(name: "1.0.4")
        try repo.tag(name: "v2.0.1")

        let inMemRepoProvider = InMemoryGitRepositoryProvider()
        inMemRepoProvider.add(specifier: specifier, repository: repo)

        let p = AbsolutePath.root.appending(component: "repoManager")
        try fs.createDirectory(p, recursive: true)
        let repositoryManager = RepositoryManager(
            path: p,
            provider: inMemRepoProvider,
            delegate: MockResolverDelegate(),
            fileSystem: fs)

        let provider = RepositoryPackageContainerProvider(
            repositoryManager: repositoryManager,
            manifestLoader: MockManifestLoader(manifests: [:]))
        let ref = PackageReference(identity: "foo", path: repoPath.pathString)
        let container = try await { provider.getContainer(for: ref, completion: $0) }
        let v = container.versions(filter: { _ in true }).map{$0}
        XCTAssertEqual(v, ["2.0.1", "1.0.4", "1.0.2", "1.0.1", "1.0.0"])
    }
}
