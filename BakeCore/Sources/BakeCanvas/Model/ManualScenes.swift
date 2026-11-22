#if DEBUG
import BakeGraph

/// Example patches for the user manual's screenshots, opened with `-manualScene <name>`.
/// Sound comes only from Generator nodes, so no audio files or personal names appear.
public enum ManualScenes {
    public static let names = ["quickstart", "empty", "card", "clock", "batch", "group"]

    public static func project(named name: String) -> ProjectFile? {
        switch name {
        case "quickstart": quickstart()
        case "empty": ProjectFile()
        case "card": card()
        case "clock": clock()
        case "batch": batch()
        case "group": group()
        default: nil
        }
    }

    private static func quickstart() -> ProjectFile {
        var project = ProjectFile()
        let generator = project.addNode(.generator, at: CanvasPoint(x: 0, y: 0))
        let lfo = project.addNode(.lfo, at: CanvasPoint(x: 0, y: 240))
        let filters = project.addNode(.filters, at: CanvasPoint(x: 340, y: 0))
        let bake = project.addNode(.print, at: CanvasPoint(x: 680, y: 0))
        project.setModulated("cutoff", of: filters, true)
        try? project.connect(from: PinRef(node: generator, pin: "out"), to: PinRef(node: filters, pin: "in"))
        try? project.connect(from: PinRef(node: lfo, pin: "out"), to: PinRef(node: filters, pin: "mod.cutoff"))
        try? project.connect(from: PinRef(node: filters, pin: "out"), to: PinRef(node: bake, pin: "in"))
        return project
    }

    private static func card() -> ProjectFile {
        var project = ProjectFile()
        _ = project.addNode(.filters, at: CanvasPoint(x: 0, y: 0))
        return project
    }

    private static func clock() -> ProjectFile {
        var project = ProjectFile()
        let clock = project.addNode(.clock, at: CanvasPoint(x: 0, y: 0))
        let envelope = project.addNode(.envelope, at: CanvasPoint(x: 340, y: 0))
        try? project.connect(from: PinRef(node: clock, pin: "out"), to: PinRef(node: envelope, pin: "trigger"))
        return project
    }

    private static func batch() -> ProjectFile {
        var project = ProjectFile()
        let source = project.addNode(.batchAudio, at: CanvasPoint(x: 0, y: 0))
        let filters = project.addNode(.filters, at: CanvasPoint(x: 340, y: 0))
        let sink = project.addNode(.batchBake, at: CanvasPoint(x: 680, y: 0))
        try? project.connect(from: PinRef(node: source, pin: "out"), to: PinRef(node: filters, pin: "in"))
        try? project.connect(from: PinRef(node: filters, pin: "out"), to: PinRef(node: sink, pin: "in"))
        return project
    }

    private static func group() -> ProjectFile {
        var project = quickstart()
        let ids = Set(project.nodes.filter { $0.kind == .filters || $0.kind == .lfo }.map(\.id))
        _ = project.groupNodes(ids, name: "Wobble")
        return project
    }
}
#endif
