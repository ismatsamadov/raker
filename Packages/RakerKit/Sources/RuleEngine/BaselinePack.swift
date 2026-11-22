import Foundation

extension RulePackLoader {
    /// The baseline pack that ships inside the app, so cleanup works offline.
    public static func baseline() throws(RulePackError) -> RulePack {
        guard let url = baselineURL() else {
            throw .unreadable("baseline-pack.json is missing from the app")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        return try decode(data)
    }

    /// Looks in the app's Resources folder first: SwiftPM's generated accessor only checks the
    /// bundle root, where nothing may live in a signed app.
    private static func baselineURL() -> URL? {
        let bundleName = "RakerKit_RuleEngine.bundle"
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent(bundleName)),
           let url = bundle.url(forResource: "baseline-pack", withExtension: "json") {
            return url
        }
        return Bundle.module.url(forResource: "baseline-pack", withExtension: "json")
    }
}
