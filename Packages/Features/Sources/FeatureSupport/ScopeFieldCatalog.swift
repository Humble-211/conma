import SwiftUI
import Domain

public struct ScopeFieldDefinition: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case integer, decimal, text, toggle, choice([String]) }
    public let key: String
    public let kind: Kind
    public let unitKey: String?
    public init(key: String, kind: Kind, unitKey: String? = nil) { self.key = key; self.kind = kind; self.unitKey = unitKey }
}

/// Spec Appendix B. Keys are catalog ids; labels come from the String Catalog as `scope.field.<key>`.
public enum ScopeFieldCatalog {
    public static let customPrefix = "custom:"

    public static let common: [ScopeFieldDefinition] = [
        ScopeFieldDefinition(key: "squareFootage", kind: .decimal, unitKey: "sqft"),
        ScopeFieldDefinition(key: "rooms", kind: .integer),
        ScopeFieldDefinition(key: "floors", kind: .integer),
        ScopeFieldDefinition(key: "itemsToRepair", kind: .integer),
        ScopeFieldDefinition(key: "itemsToInstall", kind: .integer),
    ]

    private static let byType: [JobType: [ScopeFieldDefinition]] = [
        .generalRenovation: [ScopeFieldDefinition(key: "bathrooms", kind: .integer), ScopeFieldDefinition(key: "windows", kind: .integer), ScopeFieldDefinition(key: "doors", kind: .integer)],
        .basementRenovation: [ScopeFieldDefinition(key: "bedrooms", kind: .integer), ScopeFieldDefinition(key: "bathrooms", kind: .integer), ScopeFieldDefinition(key: "egressWindows", kind: .integer),
                              ScopeFieldDefinition(key: "ceilingHeight", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "wetBar", kind: .toggle)],
        .kitchen: [ScopeFieldDefinition(key: "cabinetLinearFeet", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "countertopType", kind: .choice(["laminate", "quartz", "granite", "butcherBlock", "other"])),
                   ScopeFieldDefinition(key: "appliances", kind: .integer), ScopeFieldDefinition(key: "island", kind: .toggle), ScopeFieldDefinition(key: "backsplashSqft", kind: .decimal, unitKey: "sqft")],
        .bathroom: [ScopeFieldDefinition(key: "fixtures", kind: .integer), ScopeFieldDefinition(key: "tub", kind: .toggle), ScopeFieldDefinition(key: "shower", kind: .toggle),
                    ScopeFieldDefinition(key: "vanity", kind: .toggle), ScopeFieldDefinition(key: "toilet", kind: .toggle), ScopeFieldDefinition(key: "tileSqft", kind: .decimal, unitKey: "sqft")],
        .landscaping: [ScopeFieldDefinition(key: "lotSize", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "grassArea", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "patioArea", kind: .decimal, unitKey: "sqft"),
                       ScopeFieldDefinition(key: "fenceLength", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "trees", kind: .integer), ScopeFieldDefinition(key: "irrigation", kind: .toggle)],
        .roofing: [ScopeFieldDefinition(key: "roofSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "roofType", kind: .choice(["asphaltShingle", "metal", "flat", "cedar", "tile", "other"])),
                   ScopeFieldDefinition(key: "slopes", kind: .integer), ScopeFieldDefinition(key: "layersToRemove", kind: .integer), ScopeFieldDefinition(key: "materialType", kind: .text)],
        .plumbing: [ScopeFieldDefinition(key: "fixtures", kind: .integer), ScopeFieldDefinition(key: "bathrooms", kind: .integer), ScopeFieldDefinition(key: "waterHeater", kind: .toggle), ScopeFieldDefinition(key: "repipe", kind: .toggle)],
        .electrical: [ScopeFieldDefinition(key: "outlets", kind: .integer), ScopeFieldDefinition(key: "switches", kind: .integer), ScopeFieldDefinition(key: "lightFixtures", kind: .integer),
                      ScopeFieldDefinition(key: "panelUpgrade", kind: .toggle), ScopeFieldDefinition(key: "panelAmps", kind: .choice(["amps100", "amps200", "other"]))],
        .hvac: [ScopeFieldDefinition(key: "systemType", kind: .choice(["furnace", "heatPump", "centralAir", "ductless", "other"])), ScopeFieldDefinition(key: "units", kind: .integer),
                ScopeFieldDefinition(key: "ductworkFeet", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "thermostats", kind: .integer)],
        .flooring: [ScopeFieldDefinition(key: "floorSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "flooringType", kind: .choice(["hardwood", "laminate", "vinyl", "tile", "carpet", "other"])),
                    ScopeFieldDefinition(key: "stairs", kind: .integer), ScopeFieldDefinition(key: "removalRequired", kind: .toggle)],
        .painting: [ScopeFieldDefinition(key: "wallSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "ceilingSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "doors", kind: .integer),
                    ScopeFieldDefinition(key: "trimLinearFeet", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "coats", kind: .integer)],
        .drywall: [ScopeFieldDefinition(key: "sheets", kind: .integer), ScopeFieldDefinition(key: "drywallSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "ceilings", kind: .toggle),
                   ScopeFieldDefinition(key: "finishLevel", kind: .choice(["level3", "level4", "level5"]))],
        .concrete: [ScopeFieldDefinition(key: "concreteSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "thicknessInches", kind: .decimal, unitKey: "in"),
                    ScopeFieldDefinition(key: "concreteType", kind: .choice(["slab", "driveway", "sidewalk", "foundation", "other"])), ScopeFieldDefinition(key: "rebar", kind: .toggle)],
        .deckFence: [ScopeFieldDefinition(key: "deckSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "fenceLength", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "fenceHeight", kind: .decimal, unitKey: "ft"),
                     ScopeFieldDefinition(key: "deckMaterial", kind: .choice(["pressureTreated", "cedar", "composite", "vinyl", "other"])), ScopeFieldDefinition(key: "stairs", kind: .integer), ScopeFieldDefinition(key: "railingFeet", kind: .decimal, unitKey: "ft")],
        .framing: [ScopeFieldDefinition(key: "wallLinearFeet", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "framingSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "loadBearing", kind: .toggle)],
        .windowsDoors: [ScopeFieldDefinition(key: "windows", kind: .integer), ScopeFieldDefinition(key: "doors", kind: .integer), ScopeFieldDefinition(key: "exteriorDoors", kind: .integer), ScopeFieldDefinition(key: "patioDoors", kind: .integer)],
        .exterior: [ScopeFieldDefinition(key: "sidingSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "sidingType", kind: .choice(["vinyl", "wood", "fiberCement", "brick", "stucco", "other"])),
                    ScopeFieldDefinition(key: "soffitFeet", kind: .decimal, unitKey: "ft"), ScopeFieldDefinition(key: "gutterFeet", kind: .decimal, unitKey: "ft")],
        .demolition: [ScopeFieldDefinition(key: "demoSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "dumpsters", kind: .integer), ScopeFieldDefinition(key: "hazardousMaterials", kind: .toggle)],
        .commercial: [ScopeFieldDefinition(key: "commercialSqft", kind: .decimal, unitKey: "sqft"), ScopeFieldDefinition(key: "units", kind: .integer), ScopeFieldDefinition(key: "permitsRequired", kind: .toggle)],
        .other: [],
    ]

    public static func fields(for type: JobType) -> [ScopeFieldDefinition] { common + (byType[type] ?? []) }

    public static func definition(forKey key: String) -> ScopeFieldDefinition? {
        (common + byType.values.flatMap { $0 }).first { $0.key == key }
    }

    public static func isCustom(_ key: String) -> Bool { key.hasPrefix(customPrefix) }
    public static func customLabel(_ key: String) -> String { String(key.dropFirst(customPrefix.count)) }

    /// nil for custom keys (show verbatim).
    public static func labelKey(forFieldKey key: String) -> LocalizedStringKey? {
        isCustom(key) ? nil : LocalizedStringKey("scope.field." + key)
    }
    public static func optionLabelKey(_ option: String) -> LocalizedStringKey { LocalizedStringKey("scope.option." + option) }
    public static func unitLabelKey(_ unit: String) -> LocalizedStringKey { LocalizedStringKey("scope.unit." + unit) }
}
