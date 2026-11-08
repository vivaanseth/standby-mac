import AppKit
import EventKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var controller: StandbyController

    var body: some View {
        TabView {
            GeneralSettings(store: store, controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
            ViewsSettings(store: store)
                .tabItem { Label("Views", systemImage: "rectangle.3.group") }
            ExternalSettings(store: store)
                .tabItem { Label("External", systemImage: "display.2") }
            WidgetsSettings(store: store)
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
            ClockSettings(store: store)
                .tabItem { Label("Clock", systemImage: "clock") }
            PhotosSettings(store: store)
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
            DisplaySettings(store: store)
                .tabItem { Label("Display", systemImage: "sun.max") }
        }
        .padding(.top, 6)
        .frame(minWidth: 680, minHeight: 560)
    }
}

// MARK: General

private let delayChoices: [Double] = [10, 30, 60, 120, 180, 300, 600, 900, 1200, 1800, 3600]

private func delayLabel(_ seconds: Double) -> String {
    let s = Int(seconds)
    if s < 60 { return "\(s) seconds" }
    if s < 3600 { return s == 60 ? "1 minute" : "\(s / 60) minutes" }
    return s == 3600 ? "1 hour" : "\(s / 3600) hours"
}

struct GeneralSettings: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var controller: StandbyController
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable Standby", isOn: $store.config.enabled)
                LabeledContent("Status") {
                    Text(controller.statusText).foregroundStyle(.secondary)
                }
                LabeledContent("Try it") {
                    HStack {
                        Button("Show Standby Now") { controller.startNow() }
                        if store.config.hotKeyEnabled {
                            Text("⌃⌥⌘S").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Toggle("Show Standby on the built-in display when it isn't in use", isOn: $store.config.dualEnabled)
                Picker("Start after the built-in display is unused for", selection: $store.config.dualIdleDelay) {
                    ForEach(delayChoices, id: \.self) { Text(delayLabel($0)).tag($0) }
                }
                .disabled(!store.config.dualEnabled)
                Toggle("Wake when the pointer moves onto the built-in display", isOn: $store.config.wakeOnPointerDual)
                    .disabled(!store.config.dualEnabled)
            } header: {
                Text("With an External Display")
            } footer: {
                Text("Keep working on your other display while Standby runs on your MacBook screen. Moving the pointer, clicking, scrolling or typing into a window on the built-in display counts as using it. Click the built-in display to wake it; swipe with two fingers to change views.")
                    .settingsFootnote()
            }

            Section {
                Toggle("Use Standby as a screen saver", isOn: $store.config.soloEnabled)
                Picker("Start after your Mac is idle for", selection: $store.config.soloIdleDelay) {
                    ForEach(delayChoices, id: \.self) { Text(delayLabel($0)).tag($0) }
                }
                .disabled(!store.config.soloEnabled)
                Toggle("Wake on pointer movement", isOn: $store.config.wakeOnPointerSolo)
                    .disabled(!store.config.soloEnabled)
            } header: {
                Text("When the Built-in Display Is the Only Display")
            } footer: {
                Text("Any key, click, or (if enabled) pointer movement wakes your Mac. Arrow keys change views instead of waking.")
                    .settingsFootnote()
            }

            Section("Conditions") {
                Toggle("Only start when connected to power", isOn: $store.config.onlyWhenCharging)
                Toggle("Don't start while an app keeps your Mac awake (Caffeinate, Amphetamine, videos, calls)", isOn: $store.config.respectDisplaySleepAssertions)
                Toggle("Get out of the way when an AI or app captures or controls the screen", isOn: $store.config.yieldToAgents)
                Toggle("Keep the display awake while Standby is showing", isOn: $store.config.keepDisplayAwake)
            }

            Section("System") {
                Toggle("Open at login", isOn: Binding(
                    get: { loginEnabled },
                    set: { value in
                        do {
                            try LoginItem.set(value)
                            loginError = nil
                        } catch {
                            loginError = "Couldn't change the login item. Move Standby to your Applications folder and try again."
                        }
                        loginEnabled = LoginItem.isEnabled
                    }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show in menu bar", isOn: $store.config.showMenuBarIcon)
                if !store.config.showMenuBarIcon {
                    Text("To get back to Settings, open Standby again from Finder or Spotlight.")
                        .settingsFootnote()
                }
                Toggle("Show or hide Standby with ⌃⌥⌘S", isOn: $store.config.hotKeyEnabled)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginEnabled = LoginItem.isEnabled }
    }
}

// MARK: External

struct ExternalSettings: View {
    @ObservedObject var store: ConfigStore
    @State private var previewPage: PageKind = .clock
    @State private var clockStyle: ClockStyle = .world

    var body: some View {
        Form {
            Section {
                PreviewCard(store: store, page: previewPage, clockStyle: previewPage == .clock ? clockStyle : nil, external: true)
                Picker("Preview", selection: $previewPage) {
                    ForEach(PageKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                Text("What your external display shows when nothing is in use. The photo folder, Night Mode schedule, weather, world clock cities, countdown and note are always shared with your MacBook.")
                    .settingsFootnote()
            }
            Section {
                Toggle("Same as built-in display", isOn: $store.config.external.useBuiltInSettings)
                Picker("Open to", selection: $store.config.external.startPage) {
                    ForEach(PageKind.allCases) { Text($0.title).tag($0) }
                }
                Picker("Open to clock face", selection: $store.config.external.startClockStyle) {
                    ForEach(ClockStyle.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Setup")
            } footer: {
                Text(store.config.external.useBuiltInSettings
                     ? "Uses the views, widgets, clock faces and brightness from the Views, Widgets and Clock tabs. Turn this off to set up the external display separately."
                     : "The external display has its own setup below.")
                    .settingsFootnote()
            }
            if !store.config.external.useBuiltInSettings {
            Section {
                Toggle("Widgets", isOn: $store.config.external.showWidgets)
                Toggle("Photos", isOn: $store.config.external.showPhotos)
                Toggle("Clock", isOn: $store.config.external.showClock)
                Toggle("Sky", isOn: $store.config.external.showSky)
                Toggle("Black", isOn: $store.config.external.showBlank)
                Button("Copy Everything from the Built-in Display") {
                    let start = store.config.external.startPage
                    let face = store.config.external.startClockStyle
                    store.config.external = store.config.profileMatchingBuiltIn()
                    store.config.external.useBuiltInSettings = false
                    store.config.external.startPage = start
                    store.config.external.startClockStyle = face
                }
            } header: {
                Text("Views")
            }
            StackSettings(stacks: $store.config.external.stacks,
                          count: $store.config.external.stackCount,
                          layout: $store.config.external.widgetLayout)
            Section {
                Toggle("Show widget backgrounds", isOn: $store.config.external.showWidgetBackgrounds)
            }
            Section("Clock") {
                Picker("Style", selection: $clockStyle) {
                    ForEach(ClockStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if clockStyle.hasTint {
                    SwatchPicker(tint: Binding(
                        get: { store.config.external.tint(for: clockStyle) },
                        set: { store.config.external.setTint($0, for: clockStyle) }))
                } else {
                    Text("The World clock can't be recolored.").foregroundStyle(.secondary)
                }
                ClockStyleList(styles: $store.config.external.clockStyles)
            }
            Section("Brightness") {
                HStack {
                    Image(systemName: "sun.min")
                    Slider(value: $store.config.external.brightness, in: 0.2...1)
                    Image(systemName: "sun.max")
                }
            }
            }
            Section {
                Toggle("Show on external displays when nothing is in use", isOn: $store.config.externalEnabled)
                Picker("Start after your Mac is idle for", selection: $store.config.externalIdleDelay) {
                    ForEach(delayChoices, id: \.self) { Text(delayLabel($0)).tag($0) }
                }
                .disabled(!store.config.externalEnabled)
                Toggle("Use as a screen saver when the lid is closed", isOn: $store.config.clamshellEnabled)
                    .disabled(!store.config.externalEnabled)
            } header: {
                Text("When Neither Display Is in Use")
            } footer: {
                Text("While you're using the external display, only the built-in display goes into Standby. Once there's no input at all, external displays get this screen too. Any key, click or pointer movement brings them back; the built-in display stays in Standby until you use it.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .onAppear {
            previewPage = store.config.external.startPage
            clockStyle = store.config.external.startClockStyle
        }
    }
}

/// Number of stacks, layout, and what's in each stack, for either display.
struct StackSettings: View {
    @Binding var stacks: [[WidgetSlot]]
    @Binding var count: Int
    @Binding var layout: WidgetLayout

    var body: some View {
        Section {
            Picker("Number of stacks", selection: $count) {
                ForEach(1...StandbyConfig.maxStacks, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            if count > 1 {
                Picker("Layout", selection: $layout) {
                    ForEach(WidgetLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(layout.summary).settingsFootnote()
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                      alignment: .leading, spacing: 16) {
                ForEach(0..<count, id: \.self) { i in
                    StackEditor(title: stackTitle(i), slots: $stacks[i])
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Stacks")
        } footer: {
            Text("Each stack is a Smart Stack: check the widgets it holds and drag to reorder. Swipe up or down on a stack (or press ↑ ↓ with the pointer over it) to flip through it; it loops around.")
                .settingsFootnote()
        }
    }
}

/// Which clock faces appear, and their order, for either display.
struct ClockStyleList: View {
    @Binding var styles: [ClockSlot]

    var body: some View {
        List {
            ForEach($styles) { $slot in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                    Toggle(slot.style.title, isOn: $slot.enabled).toggleStyle(.checkbox)
                    Spacer()
                }
            }
            .onMove { styles.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: CGFloat(styles.count) * 26 + 8)
    }
}

// MARK: Views

struct ViewsSettings: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                PreviewCard(store: store, page: previewPage)
            }
            Section {
                Toggle("Widgets", isOn: $store.config.showWidgets)
                Toggle("Photos", isOn: $store.config.showPhotos)
                Toggle("Clock", isOn: $store.config.showClock)
                Toggle("Sky", isOn: $store.config.showSky)
                Toggle("Black", isOn: $store.config.showBlank)
                Picker("Open to", selection: $store.config.startPage) {
                    ForEach(StartPage.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Views")
            } footer: {
                Text("Swipe left or right with two fingers (or press ← →) to move between views, and up or down to flip through widgets and clock styles.")
                    .settingsFootnote()
            }
            Section("Time & Weather") {
                Picker("Time format", selection: $store.config.timeFormat) {
                    ForEach(TimeFormat.allCases) { Text($0.title).tag($0) }
                }
                Picker("Temperature", selection: $store.config.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.title).tag($0) }
                }
                WeatherLocationField(store: store)
            }
        }
        .formStyle(.grouped)
    }

    private var previewPage: PageKind {
        switch store.config.startPage {
        case .lastUsed: store.config.lastPage
        case .widgets: .widgets
        case .photos: .photos
        case .clock: .clock
        case .sky: .sky
        case .blank: .blank
        }
    }
}

struct WeatherLocationField: View {
    @ObservedObject var store: ConfigStore
    @EnvironmentObject private var weather: WeatherService
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searching = false
    @State private var message: String?

    var body: some View {
        LabeledContent("Weather location") {
            if let place = store.config.weatherPlace {
                HStack {
                    VStack(alignment: .trailing) {
                        Text(place.name)
                        if let w = weather.snapshot {
                            Text("\(w.temperatureText) · \(w.condition)").font(.caption).foregroundStyle(.secondary)
                        } else if let e = weather.errorText {
                            Text(e).font(.caption).foregroundStyle(.red)
                        }
                    }
                    Button("Remove") { store.config.weatherPlace = nil }
                }
            } else {
                Text("None").foregroundStyle(.secondary)
            }
        }
        HStack {
            TextField("Search for a city", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(search)
            Button("Search", action: search)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            if searching { ProgressView().controlSize(.small) }
        }
        if let message {
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        ForEach(results) { place in
            Button {
                store.config.weatherPlace = place
                results = []
                query = ""
                message = nil
            } label: {
                HStack {
                    Text(place.name)
                    Text(place.region).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "plus.circle")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        Text("Weather comes from Open-Meteo. Only the city you choose is sent.")
            .settingsFootnote()
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        message = nil
        Task {
            do {
                results = try await WeatherService.search(q)
                if results.isEmpty { message = "No places found." }
            } catch {
                message = "Search failed. Check your internet connection."
            }
            searching = false
        }
    }
}

// MARK: Widgets

struct WidgetsSettings: View {
    @ObservedObject var store: ConfigStore
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        Form {
            Section {
                PreviewCard(store: store, page: .widgets)
            }
            StackSettings(stacks: $store.config.stacks,
                          count: $store.config.stackCount,
                          layout: $store.config.widgetLayout)
            Section("Behavior") {
                Toggle("Smart Rotate", isOn: $store.config.smartRotate)
                Picker("Rotate every", selection: $store.config.smartRotateMinutes) {
                    ForEach([1, 5, 10, 15, 30, 60], id: \.self) { Text($0 == 1 ? "1 minute" : "\($0) minutes").tag($0) }
                }
                .disabled(!store.config.smartRotate)
                Toggle("Show widget backgrounds", isOn: $store.config.showWidgetBackgrounds)
            }
            Section("Countdown") {
                TextField("Counting down to", text: $store.config.countdownTitle)
                Toggle("Next New Year", isOn: Binding(
                    get: { store.config.countdownDate == nil },
                    set: { store.config.countdownDate = $0 ? nil : Calendar.current.date(byAdding: .day, value: 30, to: Date()) }))
                if let target = store.config.countdownDate {
                    DatePicker("Date", selection: Binding(get: { target }, set: { store.config.countdownDate = $0 }),
                               displayedComponents: [.date, .hourAndMinute])
                }
            }
            Section("Note") {
                TextEditor(text: $store.config.noteText)
                    .font(.body)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
            }
            Section("World Clock") {
                WorldClockEditor(zones: $store.config.worldClockZones)
            }
            Section("Calendar") {
                LabeledContent("Up Next widget") {
                    switch calendar.status {
                    case .fullAccess:
                        Label("Access granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .notDetermined:
                        Button("Allow Calendar Access") { calendar.requestAccess() }
                    default:
                        Button("Open Privacy Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Stacks are numbered left to right, then top to bottom.
private func stackTitle(_ i: Int) -> String { "Stack \(i + 1)" }

struct StackEditor: View {
    var title: String
    @Binding var slots: [WidgetSlot]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            List {
                ForEach($slots) { $slot in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Toggle(isOn: $slot.enabled) {
                            Label(slot.kind.title, systemImage: slot.kind.symbol)
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                    }
                }
                .onMove { slots.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: CGFloat(slots.count) * 26 + 8)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WorldClockEditor: View {
    @Binding var zones: [String]
    @State private var query = ""

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        guard q.count >= 2 else { return [] }
        return Array(TimeZone.knownTimeZoneIdentifiers
            .filter { $0.localizedCaseInsensitiveContains(q) && !zones.contains($0) }
            .prefix(6))
    }

    var body: some View {
        ForEach(Array(zones.enumerated()), id: \.element) { i, id in
            HStack {
                Text(ZoneInfo.cityName(for: id))
                Text(TimeZone(identifier: id)?.localizedName(for: .shortGeneric, locale: .current) ?? id)
                    .foregroundStyle(.secondary)
                if i >= 4 {
                    Text("not shown").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    zones.removeAll { $0 == id }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        TextField("Add a city (e.g. Tokyo)", text: $query)
            .textFieldStyle(.roundedBorder)
        ForEach(matches, id: \.self) { id in
            Button {
                zones.append(id)
                query = ""
            } label: {
                HStack {
                    Text(ZoneInfo.cityName(for: id))
                    Text(id).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "plus.circle")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        Text("The widget shows the first four cities.").settingsFootnote()
    }
}

// MARK: Clock

struct ClockSettings: View {
    @ObservedObject var store: ConfigStore
    @State private var selected: ClockStyle = .digital

    var body: some View {
        Form {
            Section {
                PreviewCard(store: store, page: .clock, clockStyle: selected)
                Picker("Style", selection: $selected) {
                    ForEach(ClockStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section("Color") {
                if selected.hasTint {
                    SwatchPicker(tint: Binding(
                        get: { store.config.tint(for: selected) },
                        set: { store.config.setTint($0, for: selected) }))
                } else {
                    Text("The World clock can't be recolored.").foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("On Photos", selection: $store.config.photoClock) {
                    ForEach(OverlayClock.allCases) { Text($0.title).tag($0) }
                }
                Picker("On Sky", selection: $store.config.skyClock) {
                    ForEach(OverlayClock.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Clock on Other Views")
            } footer: {
                Text("Analog uses the Analog dial and its color, on every display. It's also a widget: add Analog Dial to any stack in the Widgets tab.")
                    .settingsFootnote()
            }
            Section {
                ClockStyleList(styles: $store.config.clockStyles)
                Toggle("Show weather on clock faces", isOn: $store.config.showWeatherOnClocks)
            } header: {
                Text("Styles")
            } footer: {
                Text("Swipe up or down on the Clock view to switch styles, in this order.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .onAppear { selected = store.config.lastClockStyle }
    }
}

struct SwatchPicker: View {
    @Binding var tint: Tint

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Tint.allCases) { t in
                Circle()
                    .fill(LinearGradient(colors: [t.light, t.base], startPoint: .top, endPoint: .bottom))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                    .padding(3)
                    .overlay(Circle().strokeBorder(t == tint ? Color.accentColor : .clear, lineWidth: 2))
                    .contentShape(Circle())
                    .onTapGesture { tint = t }
                    .help(t.title)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: Photos

struct PhotosSettings: View {
    @ObservedObject var store: ConfigStore
    @EnvironmentObject private var photos: PhotoRotator

    var body: some View {
        Form {
            Section {
                PreviewCard(store: store, page: .photos)
            }
            Section("Source") {
                LabeledContent("Folder") {
                    HStack {
                        Text((store.config.photoFolder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                LabeledContent("Found") {
                    Text(photos.isScanning ? "Looking…" : "\(photos.count) photos").foregroundStyle(.secondary)
                }
                Toggle("Shuffle", isOn: $store.config.photoShuffle)
            }
            Section("Playback") {
                Picker("Change photo every", selection: $store.config.photoInterval) {
                    ForEach([5.0, 10, 15, 30, 60, 120, 300, 600], id: \.self) { s in
                        Text(s < 60 ? "\(Int(s)) seconds" : (s == 60 ? "1 minute" : "\(Int(s / 60)) minutes")).tag(s)
                    }
                }
                Toggle("Slowly zoom and pan photos", isOn: $store.config.photoKenBurns)
                Picker("Time and date", selection: $store.config.photoClockPosition) {
                    ForEach(PhotoClockPosition.allCases) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { photos.configure(folder: store.config.photoFolder, shuffle: store.config.photoShuffle) }
        .onChange(of: store.config.photoFolder) { photos.configure(folder: store.config.photoFolder, shuffle: store.config.photoShuffle) }
        .onChange(of: store.config.photoShuffle) { photos.configure(folder: store.config.photoFolder, shuffle: store.config.photoShuffle) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder of photos for Standby. Subfolders are included."
        panel.directoryURL = URL(fileURLWithPath: (store.config.photoFolder as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            store.config.photoFolder = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}

// MARK: Display

struct DisplaySettings: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                PreviewCard(store: store, page: .clock, clockStyle: store.config.lastClockStyle)
            }
            Section("Brightness") {
                HStack {
                    Image(systemName: "sun.min")
                    Slider(value: $store.config.brightness, in: 0.2...1)
                    Image(systemName: "sun.max")
                }
            }
            Section {
                Picker("Night Mode", selection: $store.config.nightMode) {
                    ForEach(NightMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if store.config.nightMode == .scheduled {
                    DatePicker("From", selection: timeBinding(\.nightStartMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: timeBinding(\.nightEndMinutes), displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Night Mode")
            } footer: {
                Text("Night Mode turns everything a dim red so Standby is easy on your eyes in a dark room.")
                    .settingsFootnote()
            }
            Section {
                Toggle("Burn-in protection", isOn: $store.config.burnInProtection)
            } footer: {
                Text("Shifts everything by a few pixels every minute.").settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }

    private func timeBinding(_ key: WritableKeyPath<StandbyConfig, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = store.config[keyPath: key]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.config[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}

// MARK: Shared

/// A live miniature of StandBy that reflects settings as they change.
struct PreviewCard: View {
    @ObservedObject var store: ConfigStore
    var page: PageKind
    var clockStyle: ClockStyle?
    /// Shows the external display's profile, at its 16:9 shape.
    var external = false
    @StateObject private var nav = StandbyNavigator()

    var body: some View {
        let config = previewConfig
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { timeline in
            StandbyScene(date: timeline.date, config: config, nav: nav)
        }
        .aspectRatio(external ? 16 / 9 : 1.6, contentMode: .fit)
        .frame(maxWidth: external ? 520 : 480)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .onAppear { nav.apply(config) }
        .onChange(of: config) { nav.apply(config) }
    }

    /// The real settings, narrowed to the one page (and clock style) on show.
    private var previewConfig: StandbyConfig {
        var c = external ? store.config.companionConfig : store.config
        c.showWidgets = page == .widgets
        c.showPhotos = page == .photos
        c.showClock = page == .clock
        c.showSky = page == .sky
        c.showBlank = page == .blank
        c.burnInProtection = false
        if let clockStyle {
            c.clockStyles = [ClockSlot(style: clockStyle, enabled: true)]
        } else {
            c.clockStyles = [ClockSlot(style: c.enabledClockStyles.first ?? .digital, enabled: true)]
        }
        return c
    }
}

private extension Text {
    func settingsFootnote() -> some View {
        font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
