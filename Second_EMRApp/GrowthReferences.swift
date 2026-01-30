import Foundation

@MainActor
public final class GrowthReferences {

    public static let shared = GrowthReferences()

    // MARK: - Storage

    // Keyed by (standard|metric|sex) normalized
    private var datasets: [String: LMSDataset] = [:]
    private var didLoad = false

    private init() {
        preloadIfNeeded()
    }

    // MARK: - Public API

    public func preloadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        loadBundledJSONDatasets()
    }

    /// Store a dataset using normalized keys
    public func setDataset(_ ds: LMSDataset) {
        let sRaw = ds.standard.rawValue
        let mRaw = ds.metric.rawValue
        let xRaw = ds.sex.rawValue

        // Store with several variants to avoid mismatch between JSON strings and enum rawValues
        store(ds, standard: sRaw, metric: mRaw, sex: xRaw)

        // Also store common alternate spellings
        store(ds, standard: sRaw.replacingOccurrences(of: "–", with: "-"), metric: mRaw, sex: xRaw)
        store(ds, standard: sRaw, metric: mRaw.replacingOccurrences(of: "–", with: "-"), sex: xRaw)
    }

    /// Fetch dataset (preferred)
    public func datasetFor(
        standard: GrowthStandard,
        metric: GrowthMetric,
        sex: GrowthSex
    ) -> LMSDataset? {
        preloadIfNeeded()
        let k = key(standard: standard.rawValue, metric: metric.rawValue, sex: sex.rawValue)
        if let hit = datasets[k] { return hit }

        // Try normalized fallbacks
        let k2 = key(standard: normalize(standard.rawValue),
                     metric: normalize(metric.rawValue),
                     sex: normalize(sex.rawValue))
        return datasets[k2]
    }

    /// Convenience: get LMS dataset for ageDays (your percentile code can call this)
    public func lms(
        standard: GrowthStandard,
        metric: GrowthMetric,
        sex: GrowthSex,
        ageDays: Int
    ) -> LMSRow? {

        guard let ds = datasetFor(
            standard: standard,
            metric: metric,
            sex: sex
        ) else { return nil }

        // Convert the input ageDays (DOB-based) into the dataset’s unit
        let ageValue: Int
        switch ds.ageUnit {
        case .days:
            ageValue = ageDays
        case .months:
            // WHO tables are in months; use average month length
            ageValue = Int(round(Double(ageDays) / 30.4375))
        }

        // Sort by row.age (NOT ageDays)
        let rows = ds.rows.sorted(by: { (a: LMSRow, b: LMSRow) in
            a.age < b.age
        })

        // Exact match
        if let exact = rows.first(where: { $0.age == ageValue }) {
            return exact
        }

        // Nearest row
        return rows.min(by: {
            abs($0.age - ageValue) < abs($1.age - ageValue)
        })
    }

    // MARK: - Bundle loading

    private func loadBundledJSONDatasets() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []

        #if DEBUG
        print("📦 GrowthReferences: Bundle JSON count = \(urls.count)")
        #endif

        var loaded = 0

        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                let ds = try JSONDecoder().decode(LMSDataset.self, from: data)
                setDataset(ds)
                loaded += 1

                #if DEBUG
                print("✅ Loaded LMS:", url.lastPathComponent, "|", ds.standard.rawValue, ds.metric.rawValue, ds.sex.rawValue)
                #endif
            } catch {
                // Ignore non-LMS json
                #if DEBUG
                let name = url.lastPathComponent.lowercased()
                if name.contains("who") || name.contains("cdc") || name.contains("lms") || name.contains("growth") {
                    print("⚠️ GrowthReferences: failed to decode \(url.lastPathComponent) as LMSDataset")
                    print("   error: \(error)")
                }
                #endif
                continue
            }
        }

        #if DEBUG
        if loaded == 0 {
            print("❌ GrowthReferences: Loaded 0 LMSDataset files. Percentiles will be missing.")
            print("   Fix: Select LMS JSON file in Xcode → Target Membership: Second_EMRApp ✅")
            print("        Target → Build Phases → Copy Bundle Resources: include the JSON ✅")
        } else {
            print("✅ GrowthReferences: Loaded \(loaded) LMSDataset file(s). Keys:")
            print(datasets.keys.sorted().joined(separator: "\n"))
        }
        #endif
    }

    // MARK: - Key helpers

    private func store(_ ds: LMSDataset, standard: String, metric: String, sex: String) {
        let k1 = key(standard: standard, metric: metric, sex: sex)
        datasets[k1] = ds

        let k2 = key(standard: normalize(standard), metric: normalize(metric), sex: normalize(sex))
        datasets[k2] = ds
    }

    private func key(standard: String, metric: String, sex: String) -> String {
        "\(standard)|\(metric)|\(sex)"
    }

    private func normalize(_ s: String) -> String {
        s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "–", with: "-")
            .lowercased()
    }
}
