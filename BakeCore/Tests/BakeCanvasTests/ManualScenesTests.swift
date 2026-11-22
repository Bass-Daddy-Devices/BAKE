#if DEBUG
import BakeGraph
import Testing
@testable import BakeCanvas

struct ManualScenesTests {
    @Test func everyNamedSceneBuilds() {
        for name in ManualScenes.names {
            #expect(ManualScenes.project(named: name) != nil, "\(name) didn't build")
        }
        #expect(ManualScenes.project(named: "nope") == nil)
    }

    @Test func emptyIsEmpty() throws {
        let project = try #require(ManualScenes.project(named: "empty"))
        #expect(project.nodes.isEmpty)
    }

    /// The quick-start chapter's patch: Generator → Filters → Bake, an LFO on Cutoff.
    @Test func quickstartIsTheChapterTwoPatch() throws {
        let project = try #require(ManualScenes.project(named: "quickstart"))
        let kinds = project.nodes.map(\.kind)
        #expect(Set(kinds) == [.generator, .filters, .lfo, .print])
        #expect(project.edges.count == 3)
        let filters = try #require(project.nodes.first { $0.kind == .filters })
        #expect(filters.modulated.contains("cutoff"))
    }

    @Test func pinsSceneIsGeneratorIntoFilters() throws {
        let project = try #require(ManualScenes.project(named: "pins"))
        #expect(Set(project.nodes.map(\.kind)) == [.generator, .filters])
        #expect(project.edges.count == 1)
    }

    @Test func groupSceneHasOneCustomNode() throws {
        let project = try #require(ManualScenes.project(named: "group"))
        #expect(project.nodes.filter { $0.kind == .custom }.count == 1)
    }

    @Test func scenesUseNoAudioFiles() {
        for name in ManualScenes.names {
            let kinds = ManualScenes.project(named: name)?.nodes.map(\.kind) ?? []
            #expect(!kinds.contains(.audio), "\(name) uses an Audio node, which needs a file")
        }
    }
}
#endif
