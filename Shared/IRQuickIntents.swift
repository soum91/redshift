import Foundation
import AppIntents

struct IRButtonEntity: AppEntity, Codable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Remote button"
    static var defaultQuery = IRButtonQuery()
    var id: String
    var name: String
    var symbol: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)", image: .init(systemName: symbol)) }
    static func load() -> [IRButtonEntity] { AppGroup.read([IRButtonEntity].self, "widget-buttons.json") ?? [] }
}
struct IRButtonQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [IRButtonEntity] { IRButtonEntity.load().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [IRButtonEntity] { IRButtonEntity.load() }
    func entities(matching string: String) async throws -> [IRButtonEntity] { IRButtonEntity.load().filter { $0.name.localizedCaseInsensitiveContains(string) } }
}
struct IRButtonWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Remote button"
    @Parameter(title: "Button") var button: IRButtonEntity?
}
@available(iOS 18.0, *) struct IRButtonControlConfig: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Remote button"
    @Parameter(title: "Button") var button: IRButtonEntity?
}
struct SendIRButtonIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Send Remote Button"
    @Parameter(title: "Button") var button: IRButtonEntity?
    init() {}
    init(_ button: IRButtonEntity?) { self.button = button }
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        guard let id = button?.id else { throw LocalError("Choose a remote button first.") }
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let remoteID = UUID(uuidString: parts[0]),
              let remote = Store.shared.remotes.first(where: { $0.id == remoteID }),
              let key = remote.key(parts[1]), let code = key.activeCode else { throw LocalError("This button has no IR code. Learn it in Redshift first.") }
        let link = try await Store.shared.ensureLink()
        try await link.set(IRCommand.send(code, Store.shared.format))
        #endif
        return .result()
    }
}
