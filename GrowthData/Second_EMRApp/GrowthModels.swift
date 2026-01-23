import Foundation

public struct LMSDataset: Codable, Hashable {
    public let standard: GrowthStandard
    public let metric: GrowthMetric
    public let sex: GrowthSex
    public let ageUnit: GrowthAgeUnit
    public let rows: [LMSRow]

    private enum CodingKeys: String, CodingKey {
        case standard, metric, sex, ageUnit, rows
    }

    public init(standard: GrowthStandard, metric: GrowthMetric, sex: GrowthSex, ageUnit: GrowthAgeUnit, rows: [LMSRow]) {
        self.standard = standard
        self.metric = metric
        self.sex = sex
        self.ageUnit = ageUnit
        self.rows = rows
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.standard = try c.decode(GrowthStandard.self, forKey: .standard)
        self.metric = try c.decode(GrowthMetric.self, forKey: .metric)
        self.sex = try c.decode(GrowthSex.self, forKey: .sex)
        self.rows = try c.decode([LMSRow].self, forKey: .rows)
        self.ageUnit = (try? c.decode(GrowthAgeUnit.self, forKey: .ageUnit)) ?? .days
    }
}

public enum GrowthStandard: String, Codable, CaseIterable, Identifiable, Hashable {
    case who_0_2
    case cdc_2_20
    public var id: String { rawValue }
}

public enum GrowthAgeUnit: String, Codable, CaseIterable, Identifiable, Hashable {
    case days
    case months
    public var id: String { rawValue }
}

public enum GrowthMetric: String, Codable, CaseIterable, Identifiable, Hashable {
    case weightForAge
    case heightForAge
    case headCircForAge
    public var id: String { rawValue }
}

public enum GrowthSex: String, Codable, CaseIterable, Identifiable, Hashable {
    case male
    case female
    public var id: String { rawValue }
}

public struct LMSRow: Codable, Hashable {
    public let age: Int          // ✅ generic age value (days or months depending on dataset.ageUnit)
    public let L: Double
    public let M: Double
    public let S: Double

    private enum CodingKeys: String, CodingKey {
        case ageDays, ageMonths, age
        case L, M, S
    }

    public init(age: Int, L: Double, M: Double, S: Double) {
        self.age = age
        self.L = L
        self.M = M
        self.S = S
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.L = try c.decode(Double.self, forKey: .L)
        self.M = try c.decode(Double.self, forKey: .M)
        self.S = try c.decode(Double.self, forKey: .S)

        if let v = try? c.decode(Int.self, forKey: .ageDays) { self.age = v; return }
        if let v = try? c.decode(Int.self, forKey: .ageMonths) { self.age = v; return }
        if let v = try? c.decode(Int.self, forKey: .age) { self.age = v; return }

        self.age = 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(age, forKey: .age)   // ✅ always encode the normalized key
        try c.encode(L, forKey: .L)
        try c.encode(M, forKey: .M)
        try c.encode(S, forKey: .S)
    }
}
