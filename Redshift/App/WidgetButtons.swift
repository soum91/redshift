import WidgetKit
extension Store {
    func publishWidgetButtons() {
        let buttons = remotes.flatMap { remote in
            remote.keys.filter(\.isReady).map { key in
                IRButtonEntity(id: remote.id.uuidString + "/" + key.id, name: remote.name + " · " + key.label, symbol: key.symbol ?? "av.remote.fill")
            }
        }
        AppGroup.write(buttons, "widget-buttons.json")
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    }
}
