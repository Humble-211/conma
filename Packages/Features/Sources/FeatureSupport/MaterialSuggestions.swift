import Domain

public enum MaterialSuggestions {
    private static let base = ["Lumber", "Drywall", "Flooring", "Paint", "Tile", "Fasteners", "Other"]
    private static let byType: [JobType: [String]] = [
        .kitchen: ["Cabinets", "Countertop", "Backsplash", "Appliances"], .bathroom: ["Vanity", "Tub/Shower", "Toilet", "Plumbing fixtures"],
        .roofing: ["Shingles", "Underlayment", "Flashing", "Vents"], .landscaping: ["Sod", "Pavers", "Gravel", "Plants", "Fence panels"],
        .electrical: ["Wire", "Panel", "Outlets/Switches", "Fixtures"], .plumbing: ["Pipe", "Fittings", "Water heater", "Fixtures"],
        .flooring: ["Flooring", "Underlay", "Transitions"], .painting: ["Paint", "Primer", "Caulk"], .concrete: ["Concrete", "Rebar", "Forms"],
        .deckFence: ["Deck boards", "Posts", "Fence panels", "Hardware"], .exterior: ["Siding", "Soffit", "Gutters"], .drywall: ["Drywall sheets", "Mud", "Tape"],
        .hvac: ["Unit", "Ductwork", "Thermostat"], .framing: ["Lumber", "Hangers", "Sheathing"], .windowsDoors: ["Windows", "Doors", "Trim"],
    ]
    /// English labels (user data once chosen, not localized).
    public static func labels(for type: JobType?) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for label in (type.flatMap { byType[$0] } ?? []) + base where seen.insert(label).inserted { out.append(label) }
        return out
    }
}
