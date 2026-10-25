import SwiftUI
import WidgetKit
import AppIntents
@main struct RedshiftWidgets: WidgetBundle {
    var body: some Widget {
        IRButtonWidget()
        if #available(iOS 18.0, *) { IRRemoteControl() }
    }
}
struct IRButtonEntry: TimelineEntry { var date: Date; var button: IRButtonEntity? }
struct IRButtonProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> IRButtonEntry { .init(date: .now, button: nil) }
    func snapshot(for configuration: IRButtonWidgetConfig, in context: Context) async -> IRButtonEntry { entry(configuration) }
    func timeline(for configuration: IRButtonWidgetConfig, in context: Context) async -> Timeline<IRButtonEntry> { Timeline(entries: [entry(configuration)], policy: .never) }
    func entry(_ config: IRButtonWidgetConfig) -> IRButtonEntry { .init(date: .now, button: IRButtonEntity.load().first { $0.id == config.button?.id }) }
}
struct IRButtonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RedshiftRemoteButton", intent: IRButtonWidgetConfig.self, provider: IRButtonProvider()) { entry in
            IRButtonView(button: entry.button).containerBackground(for: .widget) { Color.clear }
        }.configurationDisplayName("Remote button").description("Send a chosen IR command. IR cannot confirm a device's power state.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}
struct IRButtonView: View {
    @Environment(\.widgetFamily) var family
    var button: IRButtonEntity?
    var body: some View {
        if let button {
            Button(intent: SendIRButtonIntent(button)) {
                if family == .accessoryCircular { ZStack { AccessoryWidgetBackground(); Image(systemName: button.symbol) } }
                else { Label(button.name, systemImage: button.symbol).font(.headline).lineLimit(3) }
            }.buttonStyle(.plain)
        } else { Label("Choose a learned button", systemImage: "av.remote").font(.caption) }
    }
}
@available(iOS 18.0, *) struct IRRemoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.soum91.redshift.button", intent: IRButtonControlConfig.self) { config in
            ControlWidgetButton(action: SendIRButtonIntent(config.button)) { Label(config.button?.name ?? "Choose a button", systemImage: config.button?.symbol ?? "av.remote.fill") }
        }.displayName("IR remote button").description("Send a TV, soundbar, heater or custom remote command.")
    }
}
