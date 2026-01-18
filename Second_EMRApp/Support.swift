import SwiftUI
import UIKit

/// A plain UITextView wrapped for SwiftUI that exposes the cursor/selection (selectedRange).
struct CursorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let isEditable: Bool
    var font: UIFont = .preferredFont(forTextStyle: .body)

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = font
        tv.isScrollEnabled = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        tv.delegate = context.coordinator
        tv.keyboardDismissMode = .interactive
        tv.autocorrectionType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }

        // keep selection in sync (only if it differs)
        if tv.selectedRange.location != selectedRange.location || tv.selectedRange.length != selectedRange.length {
            tv.selectedRange = selectedRange
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange

        init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            _text = text
            _selectedRange = selectedRange
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text ?? ""
            selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            selectedRange = textView.selectedRange
        }
    }
}

/// Inserts `insert` at the current cursor/selection.
func insertAtCursor(text: inout String, range: inout NSRange, insert: String) {
    guard let swiftRange = Range(range, in: text) else {
        text += insert
        range = NSRange(location: (text as NSString).length, length: 0)
        return
    }

    text.replaceSubrange(swiftRange, with: insert)

    // Move cursor to end of inserted text
    let newLoc = (text as NSString).lengthOfBytes(using: String.Encoding.utf16.rawValue)
    // Safer: compute using NSString lengths
    let ns = text as NSString
    let insertedLen = (insert as NSString).length
    let startLoc = range.location
    range = NSRange(location: startLoc + insertedLen, length: 0)
}

struct NoteHeaderCard: View {
    let headerText: String

    var body: some View {
        GroupBox {
            Text(headerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
import Foundation

extension Date {
    /// Full years elapsed from this date until now
    var ageYears: Int {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year], from: self, to: now)
        return max(0, comps.year ?? 0)
    }
}
import Foundation

// MARK: - Clinic Scheduling Helpers

public enum ClinicSchedule {

    /// Returns 15-minute slots from 10:00 to 22:00 inclusive for the given day.
    public static func timeSlots(for day: Date,
                                 startHour: Int = 10,
                                 endHour: Int = 22,
                                 stepMinutes: Int = 15,
                                 calendar: Calendar = .current) -> [Date] {

        var cal = calendar
        cal.locale = .current

        guard let start = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
              let end = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: day),
              stepMinutes > 0 else { return [] }

        var out: [Date] = []
        var t = start

        // inclusive end (shows 22:00 as last slot)
        while t <= end {
            out.append(t)
            if let next = cal.date(byAdding: .minute, value: stepMinutes, to: t) {
                t = next
            } else {
                t = t.addingTimeInterval(TimeInterval(stepMinutes * 60))
            }
        }
        return out
    }

    /// Combines the day component from `day` with the hour/minute of `time`.
    public static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let cal = calendar
        let h = cal.component(.hour, from: time)
        let m = cal.component(.minute, from: time)
        return cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
    }

    /// Normalizes a date to the start of its day (useful for grouping appointments).
    public static func startOfDay(_ day: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: day)
    }
}

import Foundation

// MARK: - Growth Charts (LMS) — WHO 0–<5y, CDC 5–20y
// Note: This is the full engine + loader. You will add the WHO/CDC LMS tables as bundled JSON files.
// Until those JSON files exist, percentiles will return nil (but the app still works).

public enum GrowthChartSource {
    case who   // 0–<5 years
    case cdc   // 5–20 years
}

public enum GrowthMetric: String {
    case weightForAge
    case heightForAge
    case bmiForAge
    case headCircForAge
}

public struct LMSPoint: Codable, Hashable {
    public let ageMonths: Int
    public let L: Double
    public let M: Double
    public let S: Double
}

/// Percentile results returned by the engine
public struct GrowthPercentiles: Hashable {
    public var weightPct: Double? = nil
    public var heightPct: Double? = nil
    public var bmiPct: Double? = nil
    public var headCircPct: Double? = nil
}

public enum GrowthEngine {

    // MARK: - Public API

    /// Returns WHO (0–<5y) percentiles, or CDC (5–20y) percentiles depending on age at measurement.
    /// - Requires: DOB + sex (male/female) + relevant measurement(s).
    public static func percentiles(patientDOB: Date,
                                   patientGender: Gender,
                                   measuredAt: Date,
                                   weightKg: Double?,
                                   heightCm: Double?,
                                   headCircCm: Double?) -> GrowthPercentiles {

        // Only male/female are supported by standard charts
        guard let sexKey = sexKey(patientGender) else { return GrowthPercentiles() }

        let ageMonths = monthsBetween(dob: patientDOB, at: measuredAt)
        if ageMonths < 0 { return GrowthPercentiles() }

        let ageYears = Double(ageMonths) / 12.0
        let source: GrowthChartSource
        if ageYears < 5.0 { source = .who }
        else if ageYears <= 20.0 { source = .cdc }
        else { return GrowthPercentiles() } // adult: no percentiles

        var out = GrowthPercentiles()

        // Weight percentile
        if let w = weightKg {
            out.weightPct = percentile(source: source, metric: .weightForAge, sexKey: sexKey, ageMonths: ageMonths, value: w)
        }

        // Height percentile
        if let h = heightCm {
            out.heightPct = percentile(source: source, metric: .heightForAge, sexKey: sexKey, ageMonths: ageMonths, value: h)
        }

        // BMI percentile
        if let w = weightKg, let h = heightCm, h > 0 {
            let bmi = w / pow(h / 100.0, 2)
            if bmi.isFinite {
                out.bmiPct = percentile(source: source, metric: .bmiForAge, sexKey: sexKey, ageMonths: ageMonths, value: bmi)
            }
        }

        // Head circumference percentile (WHO only, <5y)
        if source == .who, ageYears < 5.0, let hc = headCircCm {
            out.headCircPct = percentile(source: source, metric: .headCircForAge, sexKey: sexKey, ageMonths: ageMonths, value: hc)
        }

        return out
    }

    /// Formats a “Peds percentile line” like: Wt P50 | Ht P40 | BMI P55 | HC P60
    public static func percentileLine(_ p: GrowthPercentiles) -> String? {
        var parts: [String] = []
        if let w = p.weightPct { parts.append("Wt P\(roundPct(w))") }
        if let h = p.heightPct { parts.append("Ht P\(roundPct(h))") }
        if let b = p.bmiPct { parts.append("BMI P\(roundPct(b))") }
        if let hc = p.headCircPct { parts.append("HC P\(roundPct(hc))") }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    // MARK: - Core percentile logic

    private static func percentile(source: GrowthChartSource,
                                   metric: GrowthMetric,
                                   sexKey: String,
                                   ageMonths: Int,
                                   value: Double) -> Double? {

        guard let lms = lmsFor(source: source, metric: metric, sexKey: sexKey, ageMonths: ageMonths) else { return nil }
        guard let z = zScore(value: value, lms: lms) else { return nil }
        return normalCDF(z) * 100.0
    }

    private static func lmsFor(source: GrowthChartSource,
                               metric: GrowthMetric,
                               sexKey: String,
                               ageMonths: Int) -> LMSPoint? {
        let tableName = tableFileName(source: source, metric: metric, sexKey: sexKey)
        guard let points = GrowthTables.cachedTable(named: tableName), !points.isEmpty else { return nil }

        // exact match preferred
        if let exact = points.first(where: { $0.ageMonths == ageMonths }) { return exact }

        // otherwise, interpolate between nearest points
        let sorted = points.sorted { $0.ageMonths < $1.ageMonths }
        guard let lo = sorted.last(where: { $0.ageMonths < ageMonths }),
              let hi = sorted.first(where: { $0.ageMonths > ageMonths }) else {
            return nil
        }

        let t = Double(ageMonths - lo.ageMonths) / Double(hi.ageMonths - lo.ageMonths)
        return LMSPoint(
            ageMonths: ageMonths,
            L: lerp(lo.L, hi.L, t),
            M: lerp(lo.M, hi.M, t),
            S: lerp(lo.S, hi.S, t)
        )
    }

    private static func zScore(value: Double, lms: LMSPoint) -> Double? {
        let L = lms.L, M = lms.M, S = lms.S
        guard M > 0, S > 0 else { return nil }

        if abs(L) < 1e-9 {
            // L≈0 → log method
            return log(value / M) / S
        } else {
            return (pow(value / M, L) - 1.0) / (L * S)
        }
    }

    // MARK: - Normal CDF

    private static func normalCDF(_ z: Double) -> Double {
        // Abramowitz/Stegun approximation for erf
        return 0.5 * (1.0 + erfApprox(z / sqrt(2.0)))
    }

    private static func erfApprox(_ x: Double) -> Double {
        // Numerical approximation (good enough for percentiles)
        let sign = x >= 0 ? 1.0 : -1.0
        let a1 =  0.254829592
        let a2 = -0.284496736
        let a3 =  1.421413741
        let a4 = -1.453152027
        let a5 =  1.061405429
        let p  =  0.3275911

        let t = 1.0 / (1.0 + p * abs(x))
        let y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-x * x)
        return sign * y
    }

    // MARK: - Helpers

    private static func monthsBetween(dob: Date, at date: Date) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month], from: dob, to: date)
        return comps.month ?? 0
    }

    private static func sexKey(_ g: Gender) -> String? {
        switch g {
        case .male: return "m"
        case .female: return "f"
        case .other: return nil
        }
    }

    private static func roundPct(_ x: Double) -> Int { Int(x.rounded()) }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    // File naming convention for bundled tables
    // You will add JSON files with these exact names into your app target.
    private static func tableFileName(source: GrowthChartSource, metric: GrowthMetric, sexKey: String) -> String {
        switch source {
        case .who:
            // WHO 0–<5 years (months)
            // Examples:
            // who_weightForAge_m.json
            // who_bmiForAge_f.json
            return "who_\(metric.rawValue)_\(sexKey)"
        case .cdc:
            // CDC 5–20 years (months)
            // Examples:
            // cdc_heightForAge_m.json
            return "cdc_\(metric.rawValue)_\(sexKey)"
        }
    }
}

// MARK: - Growth Tables Loader (bundle JSON)

private enum GrowthTables {

    private static var cache: [String: [LMSPoint]] = [:]

    /// Loads and caches table named `<name>.json` from main bundle.
    static func cachedTable(named: String) -> [LMSPoint]? {
        if let cached = cache[named] { return cached }

        guard let url = Bundle.main.url(forResource: named, withExtension: "json") else {
            cache[named] = []
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let points = try JSONDecoder().decode([LMSPoint].self, from: data)
            cache[named] = points
            return points
        } catch {
            cache[named] = []
            return []
        }
    }
}

import Foundation

extension Notification.Name {
    static let openMedicalRecordsTab = Notification.Name("openMedicalRecordsTab")
}
import SwiftUI

#if canImport(UIKit)
import UIKit
import QuickLook

// MARK: - Share Sheet

public struct ShareSheet: UIViewControllerRepresentable {
    public let items: [Any]

    public init(items: [Any]) { self.items = items }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - QuickLook Preview (single file)

import SwiftUI
import QuickLook

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Print Helper

public enum PrintHelper {
    public static func printURL(_ url: URL) {
        let pc = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = url.lastPathComponent
        pc.printInfo = info
        pc.printingItem = url
        pc.present(animated: true, completionHandler: nil)
    }
}
// MARK: - Backup Payload

struct BackupPayload: Codable {
    let createdAt: Date
    let patients: [Patient]
    let notes: [RecordNote]
    let attachments: [Attachment]

    init(
        patients: [Patient],
        notes: [RecordNote],
        attachments: [Attachment]
    ) {
        self.createdAt = Date()
        self.patients = patients
        self.notes = notes
        self.attachments = attachments
    }
}

#endif
