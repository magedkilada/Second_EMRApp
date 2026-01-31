//
//  ReferencesStore.swift
//  Second_EMRApp
//

import Foundation
import Combine

public struct ReferenceItem: Identifiable, Hashable, Codable {
    public enum Category: String, CaseIterable, Codable, Hashable {
        case scales = "Clinical Scales"
        case guidelines = "Guidelines"
        case procedures = "Procedures"
        case medications = "Medications"
        case misc = "Misc"
    }

    public var id: UUID = UUID()
    public var title: String
    public var category: Category
    public var body: String
    public var isFavorite: Bool = false
    public var filePath: String? = nil

    public init(
        id: UUID = UUID(),
        title: String,
        category: Category,
        body: String,
        isFavorite: Bool = false,
        filePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.body = body
        self.isFavorite = isFavorite
        self.filePath = filePath
    }

    /// Resolved file URL, if file exists on disk.
    /// `filePath` stores a relative path (e.g. "ReferenceFiles/file.pdf"),
    /// resolved against the local Documents directory.
    public var fileURL: URL? {
        guard let path = filePath, !path.isEmpty else { return nil }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // Support both relative and legacy absolute paths
        let url: URL
        if path.hasPrefix("/") {
            if let range = path.range(of: "Documents/") {
                let relative = String(path[range.upperBound...])
                url = docs.appendingPathComponent(relative)
            } else {
                url = URL(fileURLWithPath: path)
            }
        } else {
            url = docs.appendingPathComponent(path)
        }

        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

@MainActor
public final class ReferencesStore: ObservableObject {

    @Published public var items: [ReferenceItem] = []
    @Published public var selectedCategory: ReferenceItem.Category? = nil

    private static let fileName = "references.json"

    /// Local Documents directory for all reference data.
    public static var baseDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Directory for imported reference files (PDFs, etc.)
    public static var referenceFilesDirectory: URL {
        let dir = baseDirectory.appendingPathComponent("ReferenceFiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Directory for imported reference photos
    public static var referencePhotosDirectory: URL {
        let dir = baseDirectory.appendingPathComponent("ReferencePhotos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL {
        baseDirectory.appendingPathComponent(fileName)
    }

    private static let seedVersionKey = "ReferencesStore_SeedVersion"
    private static let currentSeedVersion = 2  // Bump this when adding new default scales

    public init() {
        loadFromDisk()
        if items.isEmpty {
            loadDefaults()
            saveToDisk()
            UserDefaults.standard.set(Self.currentSeedVersion, forKey: Self.seedVersionKey)
        } else {
            seedNewDefaultsIfNeeded()
        }
    }

    /// Add any new default scales that weren't in a previous seed version,
    /// without removing the user's existing references.
    private func seedNewDefaultsIfNeeded() {
        let lastSeed = UserDefaults.standard.integer(forKey: Self.seedVersionKey)
        guard lastSeed < Self.currentSeedVersion else { return }

        let defaults = Self.defaultItems()
        let existingTitles = Set(items.map { $0.title.lowercased() })

        var added = false
        for item in defaults where !existingTitles.contains(item.title.lowercased()) {
            items.append(item)
            added = true
        }

        if added { saveToDisk() }
        UserDefaults.standard.set(Self.currentSeedVersion, forKey: Self.seedVersionKey)
    }

    public var filteredItems: [ReferenceItem] {
        guard let cat = selectedCategory else { return items }
        return items.filter { $0.category == cat }
    }

    @discardableResult
    public func addBlank() -> ReferenceItem {
        let item = ReferenceItem(title: "New Reference", category: .misc, body: "")
        items.insert(item, at: 0)
        saveToDisk()
        return item
    }

    /// Insert a new item and persist immediately.
    public func add(_ item: ReferenceItem) {
        items.insert(item, at: 0)
        saveToDisk()
    }

    public func update(_ item: ReferenceItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.insert(item, at: 0)
        }
        saveToDisk()
    }

    public func delete(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }),
           let fileURL = item.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        items.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Replace all items (used by restore).
    public func replaceAll(with newItems: [ReferenceItem]) {
        items = newItems
        saveToDisk()
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("[ReferencesStore] save error: \(error)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.fileURL)
            items = try JSONDecoder().decode([ReferenceItem].self, from: data)
        } catch {
            print("[ReferencesStore] load error: \(error)")
        }
    }

    // MARK: - Defaults
    private func loadDefaults() {
        items = Self.defaultItems()
    }

    private static func defaultItems() -> [ReferenceItem] {
        [

            // ── 1. Glasgow Coma Scale (Adult) ──────────────────────────
            ReferenceItem(
                title: "Glasgow Coma Scale (GCS)",
                category: .scales,
                body:
"""
Glasgow Coma Scale (GCS)
Total Score: 3–15

Eye Opening (E) — 1 to 4
4: Spontaneous
3: To voice / command
2: To pain / pressure
1: None

Verbal Response (V) — 1 to 5
5: Oriented
4: Confused
3: Inappropriate words
2: Incomprehensible sounds
1: None

Motor Response (M) — 1 to 6
6: Obeys commands
5: Localizes pain
4: Normal flexion (withdrawal)
3: Abnormal flexion (decorticate)
2: Extension (decerebrate)
1: None

Interpretation:
13–15: Mild brain injury
9–12: Moderate brain injury
3–8: Severe brain injury (intubation threshold)

Notes:
- GCS 8 or less = indication for intubation
- Always document best response
- Document individual components (e.g., E3V4M5 = 12)
"""
            ),

            // ── 2. Pediatric Glasgow Coma Scale ────────────────────────
            ReferenceItem(
                title: "Pediatric Glasgow Coma Scale",
                category: .scales,
                body:
"""
Pediatric Glasgow Coma Scale (pGCS)
For children < 2 years / pre-verbal
Total Score: 3–15

Eye Opening (E) — 1 to 4
4: Spontaneous
3: To voice / speech
2: To pain / pressure
1: None

Verbal Response (V) — Modified for Pre-verbal — 1 to 5
5: Coos, babbles, age-appropriate vocalization
4: Irritable, crying but consolable
3: Cries inappropriately, inconsolable
2: Moans, grunts to pain
1: None

Motor Response (M) — 1 to 6
6: Spontaneous purposeful movement / obeys
5: Localizes pain (withdraws to touch)
4: Normal flexion (withdrawal from pain)
3: Abnormal flexion (decorticate posturing)
2: Extension (decerebrate posturing)
1: None

Interpretation:
13–15: Mild
9–12: Moderate
3–8: Severe (consider intubation)

Notes:
- For verbal children (> 2 years), use standard adult GCS verbal scale
- Always document age and whether child is pre-verbal
- Assess best response; document E/V/M individually
"""
            ),

            // ── 3. Karnofsky Performance Status ────────────────────────
            ReferenceItem(
                title: "Karnofsky Performance Status (KPS)",
                category: .scales,
                body:
"""
Karnofsky Performance Status Scale (KPS)

100: Normal, no complaints, no evidence of disease
 90: Able to carry on normal activity; minor signs or symptoms of disease
 80: Normal activity with effort; some signs or symptoms of disease
 70: Cares for self; unable to carry on normal activity or do active work
 60: Requires occasional assistance but able to care for most personal needs
 50: Requires considerable assistance and frequent medical care
 40: Disabled; requires special care and assistance
 30: Severely disabled; hospitalization indicated, death not imminent
 20: Very sick; hospitalization necessary, active supportive treatment needed
 10: Moribund; fatal processes progressing rapidly
  0: Dead

Functional Categories:
100–80: Able to carry on normal activity; no special care needed
 70–50: Unable to work; able to live at home and care for most personal needs; varying amount of assistance needed
 40–10: Unable to care for self; requires institutional or hospital care

Common Uses:
- Neuro-oncology: eligibility for clinical trials (typically KPS >= 60–70)
- Prognosis estimation in brain tumors
- Radiation therapy planning
- Palliative care decision-making
"""
            ),

            // ── 4. Modified Fisher Scale ───────────────────────────────
            ReferenceItem(
                title: "Modified Fisher Scale",
                category: .scales,
                body:
"""
Modified Fisher Scale
Subarachnoid Hemorrhage (SAH) — CT Classification
Predicts risk of symptomatic vasospasm

Grade 0: No SAH or IVH
  - Vasospasm risk: ~0%

Grade 1: Thin SAH, no IVH
  - Focal or diffuse thin layer of SAH (<1 mm)
  - Vasospasm risk: ~24%

Grade 2: Thin SAH with IVH
  - Thin SAH (<1 mm) with intraventricular hemorrhage
  - Vasospasm risk: ~33%

Grade 3: Thick SAH, no IVH
  - Focal or diffuse thick layer of SAH (>=1 mm)
  - Vasospasm risk: ~33%

Grade 4: Thick SAH with IVH
  - Thick SAH (>=1 mm) with intraventricular hemorrhage
  - Vasospasm risk: ~40%

Key Points:
- "Thin" = <1 mm thick layer of blood
- "Thick" = >=1 mm thick layer of blood
- IVH = Intraventricular hemorrhage
- Higher grade = higher risk of delayed cerebral ischemia (DCI)
- Vasospasm window: typically days 3–14 post-SAH
- Peak vasospasm risk: days 7–10
"""
            ),

            // ── 5. Hunt & Hess Scale ───────────────────────────────────
            ReferenceItem(
                title: "Hunt and Hess Scale",
                category: .scales,
                body:
"""
Hunt and Hess Scale
Clinical Grading of Subarachnoid Hemorrhage (SAH)

Grade I:
  - Asymptomatic or mild headache, slight nuchal rigidity
  - Surgical risk: Low
  - Approximate mortality: 1–5%

Grade II:
  - Moderate to severe headache, nuchal rigidity
  - No neurological deficit other than cranial nerve palsy
  - Surgical risk: Low
  - Approximate mortality: 5–10%

Grade III:
  - Drowsiness, confusion, or mild focal deficit
  - Surgical risk: Moderate
  - Approximate mortality: 15–20%

Grade IV:
  - Stupor, moderate to severe hemiparesis
  - Possibly early decerebrate rigidity
  - Vegetative disturbances
  - Surgical risk: High
  - Approximate mortality: 30–40%

Grade V:
  - Deep coma, decerebrate rigidity
  - Moribund appearance
  - Surgical risk: Very high
  - Approximate mortality: 50–80%

Clinical Use:
- Grade I–III: Generally considered for early surgical/endovascular treatment
- Grade IV–V: May delay intervention; optimize medical management first
- Document on admission AND track progression
- Used in conjunction with Modified Fisher Scale for comprehensive SAH assessment
"""
            ),

            // ── 6. NIH Stroke Scale (NIHSS) ───────────────────────────
            ReferenceItem(
                title: "NIH Stroke Scale (NIHSS)",
                category: .scales,
                body:
"""
NIH Stroke Scale (NIHSS)
National Institutes of Health Stroke Scale
Total Score: 0–42

1a. Level of Consciousness (LOC) — 0–3
  0: Alert
  1: Not alert, arousable by minor stimulation
  2: Not alert, requires repeated stimulation
  3: Unresponsive or reflexive responses only

1b. LOC Questions (month, age) — 0–2
  0: Both correct
  1: One correct
  2: Neither correct

1c. LOC Commands (open/close eyes, grip/release hand) — 0–2
  0: Both correct
  1: One correct
  2: Neither correct

2. Best Gaze (horizontal eye movement) — 0–2
  0: Normal
  1: Partial gaze palsy
  2: Forced deviation or total gaze paresis

3. Visual Fields — 0–3
  0: No visual loss
  1: Partial hemianopia
  2: Complete hemianopia
  3: Bilateral hemianopia (blind)

4. Facial Palsy — 0–3
  0: Normal
  1: Minor paralysis (flattened nasolabial fold)
  2: Partial paralysis (lower face)
  3: Complete paralysis (upper and lower face)

5a. Motor Arm – Left / 5b. Motor Arm – Right — 0–4 each
  0: No drift (holds 90/45 degrees for 10 sec)
  1: Drift (holds but drifts before 10 sec)
  2: Some effort against gravity
  3: No effort against gravity
  4: No movement
  UN: Amputation or joint fusion

6a. Motor Leg – Left / 6b. Motor Leg – Right — 0–4 each
  0: No drift (holds 30 degrees for 5 sec)
  1: Drift
  2: Some effort against gravity
  3: No effort against gravity
  4: No movement
  UN: Amputation or joint fusion

7. Limb Ataxia — 0–2
  0: Absent
  1: Present in one limb
  2: Present in two or more limbs

8. Sensory — 0–2
  0: Normal
  1: Mild-to-moderate sensory loss
  2: Severe or total sensory loss

9. Best Language — 0–3
  0: No aphasia
  1: Mild-to-moderate aphasia
  2: Severe aphasia
  3: Mute / global aphasia

10. Dysarthria — 0–2
  0: Normal
  1: Mild-to-moderate slurring
  2: Severe / near-unintelligible or mute
  UN: Intubated or physical barrier

11. Extinction and Inattention (Neglect) — 0–2
  0: No abnormality
  1: Inattention to one modality (visual, tactile, auditory, spatial)
  2: Profound hemi-inattention / extinction to more than one modality

Interpretation:
  0: No stroke symptoms
  1–4: Minor stroke
  5–15: Moderate stroke
  16–20: Moderate to severe stroke
  21–42: Severe stroke

Clinical Decision Points:
- NIHSS >= 6: Consider IV tPA (within 4.5 hours of onset)
- NIHSS >= 6 with LVO: Consider mechanical thrombectomy (within 24 hours)
- Serial assessments to track improvement or deterioration
"""
            ),

            // ── 7. ICH Score ──────────────────────────────────────────
            ReferenceItem(
                title: "Intracerebral Hemorrhage (ICH) Score",
                category: .scales,
                body:
"""
ICH Score
Intracerebral Hemorrhage Grading Scale
Predicts 30-day mortality

Components (Total: 0–6):

1. GCS Score — 0–2 points
  0: GCS 13–15
  1: GCS 5–12
  2: GCS 3–4

2. ICH Volume — 0–1 point
  0: < 30 mL
  1: >= 30 mL

3. Intraventricular Hemorrhage (IVH) — 0–1 point
  0: No
  1: Yes

4. Infratentorial Origin — 0–1 point
  0: No (supratentorial)
  1: Yes (cerebellum or brainstem)

5. Age — 0–1 point
  0: < 80 years
  1: >= 80 years

30-Day Mortality by ICH Score:
  0: ~0%
  1: ~13%
  2: ~26%
  3: ~72%
  4: ~97%
  5: ~100%
  6: ~100%

ICH Volume Estimation (ABC/2 Method):
  A = largest diameter of hemorrhage on CT (cm)
  B = diameter perpendicular to A on same slice (cm)
  C = number of slices with hemorrhage x slice thickness (cm)
  Volume = (A x B x C) / 2 in mL

Key Points:
- Do NOT use as sole basis for withdrawal of care
- Useful for prognostication and family discussions
- Serial CT to assess expansion (>33% or >6 mL = significant)
- Consider surgical evacuation for cerebellar ICH > 3 cm
"""
            ),

            // ── 8. Modified JOA Score (mJOA) ──────────────────────────
            ReferenceItem(
                title: "Modified JOA (mJOA) Score - Cervical Myelopathy",
                category: .scales,
                body:
"""
Modified Japanese Orthopaedic Association (mJOA) Score
Cervical Spondylotic Myelopathy Assessment
Total Score: 0–18 (18 = normal)

I. Motor Dysfunction — Upper Extremity (0–5)
  5: Normal hand function, able to perform fine tasks
  4: Can button shirt with difficulty
  3: Can hold objects but cannot button shirt
  2: Cannot handle chopsticks/spoon, can move hands
  1: Cannot move hands, can move shoulder/elbow
  0: Complete loss of motor function in upper extremities

II. Motor Dysfunction — Lower Extremity (0–7)
  7: Normal walking ability
  6: Can walk on flat ground without cane/support
  5: Can walk on flat ground with cane/support
  4: Can walk with support, needs support on stairs
  3: Can stand but cannot walk
  2: Unable to stand, wheelchair bound
  1: Unable to move in wheelchair, bed-bound
  0: Complete loss of motor function in lower extremities

III. Sensory Dysfunction — Upper Extremity (0–3)
  3: Normal sensation
  2: Mild sensory loss or numbness
  1: Severe sensory loss or pain
  0: Complete loss of sensation

IV. Sphincter Dysfunction (0–3)
  3: Normal bladder function
  2: Mild dysfunction (frequency, hesitancy)
  1: Severe dysfunction (incontinence, retention)
  0: Complete loss of bladder function

Severity Classification:
  18: Normal (no myelopathy)
  15–17: Mild myelopathy
  12–14: Moderate myelopathy
  < 12: Severe myelopathy

Surgical Indications:
- mJOA < 12–14: Surgery generally recommended
- Declining mJOA score: Progressive myelopathy, consider early intervention
- mJOA >= 15: May consider conservative management with close follow-up

Recovery Rate (Hirabayashi):
  Recovery Rate (%) = (Postop mJOA - Preop mJOA) / (18 - Preop mJOA) x 100
  Excellent: >= 75%
  Good: 50–74%
  Fair: 25–49%
  Poor: < 25%
"""
            ),

        ]
    }
}
