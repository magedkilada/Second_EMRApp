import Foundation
import Combine

@MainActor
final class GrowthStore: ObservableObject {

    static let shared = GrowthStore()

    @Published private(set) var datasets: [String: LMSDataset] = [:]

    private init() {
        loadWHO0to2FromBundle()
    }

    // MARK: - Bundle scanning (WHO 0–2)

    private func loadWHO0to2FromBundle() {
        // Find every JSON in the app bundle, then keep only who_0_2_*.json
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []

        let names = urls
            .map { $0.deletingPathExtension().lastPathComponent }   // remove ".json"
            .filter { $0.hasPrefix("who_0_2_") }
            .sorted()

        print("📦 WHO 0–2 JSON files in bundle:", names.count)
        if names.isEmpty {
            print("⚠️ No who_0_2_*.json found. Check Copy Bundle Resources.")
        }

        loadBundleJSON(named: names)
    }

    // MARK: - Load JSON by name (without extension)

    func loadBundleJSON(named names: [String]) {
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                print("❌ Missing in bundle:", name)
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                let dataset = try JSONDecoder().decode(LMSDataset.self, from: data)
                datasets[name] = dataset
                print("✅ Loaded LMS:", name, "rows:", dataset.rows.count)
            } catch {
                print("❌ Failed to load \(name):", error)
            }
        }
    }

    // MARK: - Lookup

    /// Your filenames are your keys:
    /// who_0_2_weightForAge_male
    /// who_0_2_heightForAge_female
    /// who_0_2_headCircForAge_male
    func datasetFor(standard: GrowthStandard, metric: GrowthMetric, sex: GrowthSex) -> LMSDataset? {
        let key = "\(standard.rawValue)_\(metric.rawValue)_\(sex.rawValue)"
        return datasets[key]
    }
}
