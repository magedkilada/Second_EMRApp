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

        let docs = iCloudSyncManager.shared.baseURL

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

    /// Base directory — iCloud container if available, else local Documents.
    public static var baseDirectory: URL {
        iCloudSyncManager.shared.baseURL
    }

    /// Directory for imported reference files (PDFs, etc.)
    public static var referenceFilesDirectory: URL {
        iCloudSyncManager.shared.directoryURL(for: "ReferenceFiles")
    }

    /// Directory for imported reference photos
    public static var referencePhotosDirectory: URL {
        iCloudSyncManager.shared.directoryURL(for: "ReferencePhotos")
    }

    private static var fileURL: URL {
        iCloudSyncManager.shared.url(for: fileName)
    }

    private static let seedVersionKey = "ReferencesStore_SeedVersion"
    private static let currentSeedVersion = 6  // Bump this when adding new default scales

    public init() {
        loadFromDisk()
        if items.isEmpty {
            loadDefaults()
            saveToDisk()
            UserDefaults.standard.set(Self.currentSeedVersion, forKey: Self.seedVersionKey)
        } else {
            seedNewDefaultsIfNeeded()
        }

        iCloudSyncManager.shared.registerForChanges(filename: "references.json") { [weak self] in
            Task { @MainActor in self?.loadFromDisk() }
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

    /// Merge incoming references by UUID (add if new).
    public func mergeItems(with incoming: [ReferenceItem]) -> Int {
        let existingIDs = Set(items.map { $0.id })
        let newItems = incoming.filter { !existingIDs.contains($0.id) }

        if !newItems.isEmpty {
            items.append(contentsOf: newItems)
            saveToDisk()
        }
        return newItems.count
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

            // ── 9. SLIC — Subaxial Cervical Injury Classification ─────
            ReferenceItem(
                title: "Subaxial Injury Classification (SLIC) System",
                category: .scales,
                body:
"""
Subaxial Cervical Spine Injury Classification (SLIC)
(Vaccaro et al., 2007)
Applies to C3–C7 subaxial cervical spine injuries
Total Score: 0–10+

1. MORPHOLOGY — 0–4 points
  0: No abnormality
  1: Compression fracture
  2: Burst fracture
  3: Distraction injury (e.g., facet perch, hyperextension)
  4: Rotation / translation injury (e.g., facet dislocation, unstable teardrop, bilateral pedicle fracture)

2. DISCO-LIGAMENTOUS COMPLEX (DLC) — 0–2 points
  0: Intact
  1: Indeterminate (MRI signal change, isolated interspinous widening)
  2: Disrupted (widened disc space, facet perch/dislocation, kyphotic deformity)

Key Indicators of DLC Disruption:
  - Widened interspinous space
  - Facet subluxation or dislocation
  - Abnormal MRI signal in posterior ligaments
  - Widened disc space anteriorly

3. NEUROLOGICAL STATUS — 0–4 points
  0: Intact
  1: Root injury (radiculopathy)
  2: Complete spinal cord injury
  3: Incomplete spinal cord injury (e.g., central cord, Brown-Séquard)
  +1: Ongoing cord compression with neuro deficit (modifier)

Treatment Algorithm:
  Score 1–3: Non-operative management (rigid collar, halo)
  Score 4: May be treated operatively OR non-operatively (surgeon discretion)
  Score >= 5: Operative management recommended

Surgical Approach Considerations:
  - Anterior compression → anterior approach (corpectomy/ACDF)
  - Posterior ligamentous disruption → posterior approach (lateral mass screws)
  - Combined injuries → combined anterior-posterior approach (360°)

Notes:
  - Always assess all 3 components independently
  - MRI is essential to evaluate DLC status
  - Consider patient factors (age, comorbidities, pre-existing stenosis)
  - SLIC does not apply to occipital-C2 injuries
"""
            ),

            // ── 10. AO Spine Thoracolumbar Classification ─────────────
            ReferenceItem(
                title: "AO Spine Thoracolumbar Injury Classification",
                category: .scales,
                body:
"""
AO Spine Thoracolumbar Injury Classification System
(Vaccaro et al., 2013 — Global Standard)
Applies to T1–L5 thoracolumbar spine injuries

═══ INJURY MORPHOLOGY (Type A, B, C) ═══

TYPE A — Compression Injuries (Vertebral body)
  A0: Minor, non-structural fracture (spinous/transverse process)
  A1: Wedge compression / impaction fracture
      - Single endplate involvement
      - Posterior wall intact
  A2: Split / pincer-type fracture
      - Both endplates involved (coronal or sagittal split)
      - Posterior wall intact
  A3: Incomplete burst fracture
      - Single endplate + posterior wall involvement
      - Retropulsed fragment into canal
  A4: Complete burst fracture
      - Both endplates + posterior wall involvement

TYPE B — Tension Band Injuries (Posterior or anterior distraction)
  B1: Transosseous tension band failure (Chance fracture)
      - Bony posterior element fracture extending through vertebral body
  B2: Posterior tension band disruption (ligamentous)
      - Posterior ligamentous complex failure
      - With Type A fracture of vertebral body
  B3: Anterior tension band disruption (hyperextension)
      - Anterior longitudinal ligament / disc disruption
      - Rare; seen in ankylosing spondylitis / DISH

TYPE C — Displacement / Translation
  - Any injury with displacement or translation in ANY plane
  - Includes facet dislocations, shear injuries
  - Most unstable morphology

═══ NEUROLOGICAL STATUS (N) ═══
  N0: Neurologically intact
  N1: Transient neurological deficit (resolved)
  N2: Radiculopathy
  N3: Incomplete spinal cord injury / cauda equina
  N4: Complete spinal cord injury
  NX: Cannot be examined (intubated, sedated, polytrauma)

═══ PATIENT-SPECIFIC MODIFIERS (M) ═══
  M1: Indeterminate significance (e.g., posterior ligamentous complex unclear on MRI)
  M2: Patient-specific comorbidity affecting treatment
      - Ankylosing spondylitis / DISH
      - Osteoporosis
      - Metabolic bone disease

═══ TREATMENT GUIDELINES (AO Spine TL Score) ═══
  A0, A1, A2 + N0: Non-operative (TLSO brace)
  A3, A4 + N0: Consider operative (depends on kyphosis, canal compromise)
  Any B or C type: Operative management recommended
  Any N3 or N4: Operative with decompression
  M2 modifiers: Lower threshold for surgical fixation

Classification Format Example:
  T12 fracture: A4 + N3 + M1 = Complete burst, incomplete SCI, indeterminate PLC

Notes:
  - CT is essential for morphology classification
  - MRI for neurological status and PLC integrity
  - Replace the older Denis and Magerl classifications
  - Used globally as the current standard
"""
            ),

            // ── 11. Denis Classification — Sacral Fractures ───────────
            ReferenceItem(
                title: "Denis Classification for Sacral Fractures",
                category: .scales,
                body:
"""
Denis Classification of Sacral Fractures
(Denis, Davis & Comfort, 1988)
Based on fracture location relative to sacral foramina

═══ THREE ZONES ═══

ZONE I — Lateral to Sacral Foramina (Alar Region)
  - Most common (50%)
  - Fracture through sacral ala
  - Typically associated with pelvic ring injuries
  - Neurological deficit: ~6%
  - Nerve injury: L5 root (foot drop)
  - Mechanism: Lateral compression

ZONE II — Through Sacral Foramina (Foraminal Region)
  - Second most common (34%)
  - Fracture line passes through one or more neural foramina
  - Neurological deficit: ~28%
  - Nerve injury: S1, S2 roots (sciatica, calf weakness)
  - May cause unilateral sacral nerve root injury
  - Mechanism: Lateral compression or vertical shear

ZONE III — Medial to Sacral Foramina (Central/Canal Region)
  - Least common (16%)
  - Fracture involves the sacral canal
  - Neurological deficit: ~57%
  - Nerve injury: S2–S5 roots
  - Bowel/bladder/sexual dysfunction common
  - May cause cauda equina syndrome
  - Mechanism: Direct blow, vertical shear

═══ ASSOCIATED INJURIES ═══
  - Zone I: LC-type pelvic ring fractures, L5 transverse process fractures
  - Zone II: Pelvic ring disruption, SI joint injury
  - Zone III: Bilateral sacral fractures (U-shaped/H-shaped), spinal-pelvic dissociation

═══ CLINICAL PEARLS ═══
  - Always perform rectal exam and perianal sensation testing
  - CT with coronal/sagittal reformats is the imaging standard
  - MRI for nerve root assessment if neurological deficit present
  - Zone I fractures often missed on AP pelvis radiographs
  - Zone III fractures may require lumbopelvic fixation
  - Serial neurological exams for all sacral fractures
  - Document bladder function (post-void residual)

═══ TREATMENT PRINCIPLES ═══
  Zone I: Usually non-operative (weight-bearing as tolerated)
  Zone II: Operative if displaced, unstable pelvic ring, or neuro deficit
  Zone III: Operative — lumbopelvic fixation ± decompression
  - Neurological deficit + canal compression = surgical decompression
"""
            ),

            // ── 12. AO Spine Sacral Classification ────────────────────
            ReferenceItem(
                title: "AO Spine Sacral Classification",
                category: .scales,
                body:
"""
AO Spine Sacral Fracture Classification
(Defined sacral fractures analogous to the AO thoracolumbar system)

═══ TYPE A — Compression / Lower Sacral Injuries ═══

  A0: Minor fracture
      - Coccyx fracture
      - Isolated transverse sacral fracture below S2
      - Non-structural

  A1: Lower sacrococcygeal fracture
      - Below S3, no pelvic ring involvement
      - Typically stable

  A2: Sacral body compression
      - Sacral alar fracture (Denis Zone I equivalent)
      - Unilateral, no canal involvement

═══ TYPE B — Tension Band / Posterior Pelvic Ring ═══

  B1: Unilateral posterior pelvic ring injury
      - Fracture through sacral foramina (Denis Zone II)
      - Unilateral posterior tension band failure
      - With or without anterior pelvic ring injury

  B2: Bilateral posterior pelvic ring injury
      - Bilateral sacral fractures
      - H-type or U-type fracture pattern
      - Involves sacral canal (Denis Zone III)
      - High risk of neurological deficit

  B3: Sacroiliac joint disruption
      - Posterior pelvic ring injury through SI joint
      - Ligamentous disruption vs. fracture-dislocation

═══ TYPE C — Displacement / Sacral U-type ═══

  C0: Non-displaced U-type sacral fracture
      - Bilateral vertical + transverse component
      - Potential for spinopelvic dissociation

  C1: Displaced U-type sacral fracture
      - Frank spinopelvic dissociation
      - Kyphotic angulation of upper sacral fragment
      - Almost always requires lumbopelvic fixation

  C2: Sacral burst or highly comminuted
      - Severe canal compromise
      - Associated with high-energy mechanism

═══ NEUROLOGICAL STATUS (N) ═══
  N0: Intact
  N1: Transient deficit
  N2: Radiculopathy (L5, S1)
  N3: Cauda equina — incomplete (partial bowel/bladder)
  N4: Cauda equina — complete (absent bowel/bladder/perianal)
  NX: Unknown / unable to assess

═══ MODIFIERS (M) ═══
  M1: Posterior soft tissue injury (Morel-Lavallée lesion, degloving)
  M2: Comorbidity affecting treatment (osteoporosis, ankylosing spondylitis)
  M3: Metabolic bone disease

═══ TREATMENT PRINCIPLES ═══
  A0–A1: Non-operative (symptomatic care)
  A2, B1 without neuro deficit: Non-operative vs. percutaneous SI screw fixation
  B2, B3: Operative — posterior fixation ± SI screws
  C0 non-displaced: May consider non-operative with close imaging follow-up
  C1–C2: Operative — lumbopelvic fixation (L4/L5 to ilium)
  Neurological deficit (N3, N4): Decompression + fixation
"""
            ),

            // ── 13. Young-Burgess Classification — Pelvic Fractures ───
            ReferenceItem(
                title: "Young-Burgess Classification for Pelvic Fractures",
                category: .scales,
                body:
"""
Young-Burgess Classification of Pelvic Ring Injuries
Based on mechanism of injury and vector of force

═══ LC — LATERAL COMPRESSION ═══
(Most common mechanism, ~60% of pelvic fractures)

  LC-I: Anterior sacral crush fracture + ipsilateral ramus fracture
    - Transverse ramus fracture(s)
    - Sacral buckle/impaction fracture
    - Internal rotation of hemipelvis
    - Stable / low risk of hemorrhage
    - Blood loss: ~500 mL

  LC-II: LC-I + ipsilateral posterior iliac wing fracture (crescent fracture)
    - Iliac wing fracture with partial SI joint disruption
    - Internal rotation of hemipelvis
    - Moderately unstable rotationally
    - Blood loss: ~1000 mL

  LC-III: LC-I or LC-II ipsilateral + contralateral APC injury (windswept pelvis)
    - Contralateral external rotation
    - "Windswept" pelvis appearance
    - Rotationally AND vertically unstable
    - High risk of hemorrhage
    - Blood loss: ~2000+ mL

═══ APC — ANTEROPOSTERIOR COMPRESSION (OPEN BOOK) ═══

  APC-I: Symphysis diastasis < 2.5 cm
    - Symphyseal sprain or minor widening
    - Anterior SI ligaments intact
    - Stable
    - Blood loss: ~500 mL

  APC-II: Symphysis diastasis > 2.5 cm + anterior SI joint disruption
    - Anterior SI ligaments torn
    - Posterior SI ligaments intact (sacrospinous, sacrotuberous torn)
    - "Open book" pelvis
    - Rotationally unstable, vertically stable
    - Blood loss: ~2000 mL

  APC-III: Complete SI disruption (anterior + posterior ligaments)
    - Complete posterior ring disruption
    - Rotationally AND vertically unstable
    - Highest risk of hemorrhage
    - Blood loss: ~3000+ mL
    - Associated with massive pelvic hemorrhage

═══ VS — VERTICAL SHEAR ═══

  VS: Vertical displacement of hemipelvis
    - Complete disruption of all ligaments (anterior + posterior)
    - Symphysis disrupted or vertical ramus fracture
    - Sacral fracture or SI dislocation
    - Vertical displacement visible on AP pelvis
    - Completely unstable
    - Blood loss: ~3000+ mL

═══ CM — COMBINED MECHANISM ═══

  CM: Combination of LC + APC or VS patterns
    - Often seen in high-energy polytrauma
    - Treat based on dominant instability pattern
    - Highly unstable

═══ STABILITY SUMMARY ═══
  Stable:           LC-I, APC-I
  Rotationally unstable: LC-II, APC-II
  Completely unstable:   LC-III, APC-III, VS, CM

═══ MANAGEMENT PRINCIPLES ═══
  LC-I, APC-I: Non-operative (weight-bearing as tolerated)
  LC-II: Percutaneous SI screw or anterior plate fixation
  APC-II: Symphyseal plate + anterior SI screw fixation
  LC-III, APC-III, VS: Pelvic binder emergently → operative fixation
    - Anterior fixation (symphyseal plate / external fixator)
    - Posterior fixation (SI screws, lumbopelvic fixation)
  Hemodynamically unstable:
    - Pelvic binder immediately
    - Massive transfusion protocol
    - Consider preperitoneal packing or angioembolization
    - REBOA as bridge in extremis

═══ ASSOCIATED INJURIES ═══
  - Urethral/bladder injury (APC pattern, males)
  - Vaginal laceration (open fracture)
  - Rectal injury (open fracture — high mortality)
  - Lumbosacral plexus injury (L5 root with sacral fractures)
  - Hemorrhagic shock (posterior ring disruption)
  - Morel-Lavallée lesion (closed degloving)
"""
            ),

            // ── 14. Harvard / ENLS / BTF ICP Protocol ──────────────────
            ReferenceItem(
                title: "Harvard / ENLS / BTF ICP Protocol with Weight-Based Dosing & CRRT/HD Addendum",
                category: .guidelines,
                body:
"""
Harvard / ENLS / BTF ICP Management Protocol
with Weight-Based Dosing & CRRT/HD Addendum

═══ GOALS ═══
  ICP < 22 mmHg
  CPP 60–70 mmHg (adults)
  CPP 40–50 mmHg (pediatric)
  PbtO₂ > 20 mmHg (if monitored)
  Serum Na⁺ target: 145–155 mEq/L (for hyperosmolar therapy)
  Serum Osm target: 300–320 mOsm/L

═══ TIER 0 — GENERAL MEASURES (ALL PATIENTS) ═══
  • Head of bed 30° elevation
  • Head midline (avoid jugular venous obstruction)
  • Loosen cervical collar if present
  • Normothermia (T < 38°C; treat fever aggressively)
  • Normoglycemia (glucose 100–180 mg/dL)
  • Normocarbia (PaCO₂ 35–40 mmHg)
  • Adequate sedation and analgesia
  • Seizure prophylaxis: Levetiracetam 500–1000 mg IV q12h × 7 days
  • Avoid hypotension: MAP > 80 mmHg
  • ICP monitor / EVD placed per BTF criteria

═══ TIER 1 — FIRST-LINE ICP MANAGEMENT ═══
(ICP > 22 mmHg for > 5 minutes)

  1. CSF Drainage via EVD
     • Drain 3–5 mL CSF, reassess
     • Keep EVD at 10–15 cmH₂O above tragus
     • Monitor drainage volume (max ~20 mL/hr)

  2. Sedation Optimization
     • Propofol 20–75 mcg/kg/min (preferred for neuro exams)
       OR
     • Midazolam 0.02–0.1 mg/kg/hr
     • Fentanyl 0.5–2 mcg/kg/hr for analgesia
     • Target RASS -2 to -3

  3. Hyperosmolar Therapy (First-Line Bolus)
     ┌─────────────────────────────────────────────┐
     │ Hypertonic Saline (23.4%)                   │
     │ Dose: 0.5–1 mL/kg IV bolus over 10–20 min  │
     │ via central line ONLY                        │
     │ Max single dose: 30 mL (for 23.4%)          │
     │ Check Na⁺ q4–6h; hold if Na⁺ > 160 mEq/L   │
     │ Check serum Osm q6h; hold if > 320 mOsm/L  │
     └─────────────────────────────────────────────┘
     ┌─────────────────────────────────────────────┐
     │ Alternative: 3% NaCl infusion               │
     │ 150–250 mL bolus over 15–20 min             │
     │ OR continuous 0.5–1 mL/kg/hr                │
     │ Peripheral or central line OK               │
     └─────────────────────────────────────────────┘
     ┌─────────────────────────────────────────────┐
     │ Mannitol 20%                                │
     │ Dose: 0.25–1 g/kg IV bolus over 15–20 min  │
     │ (1 g/kg = 5 mL/kg of 20% mannitol)         │
     │ May repeat q4–6h                            │
     │ Hold if serum Osm > 320 mOsm/L             │
     │ Hold if osmolar gap > 20                    │
     │ Replace urinary losses (UOP may surge)      │
     │ ⚠ Avoid in hypotension / hypovolemia       │
     └─────────────────────────────────────────────┘

═══ TIER 2 — SECOND-LINE ICP MANAGEMENT ═══
(Refractory to Tier 1 after 15–30 min)

  4. Neuromuscular Blockade
     • Cisatracurium 0.15 mg/kg bolus → 1–3 mcg/kg/min infusion
       OR
     • Vecuronium 0.1 mg/kg bolus → 0.05–0.1 mg/kg/hr
     • Train-of-four monitoring (target 1–2 twitches)
     • Must have continuous EEG if paralyzed + comatose

  5. Moderate Hyperventilation
     • PaCO₂ 30–35 mmHg (brief, < 6 hours if possible)
     • ⚠ Avoid PaCO₂ < 30 mmHg (risk of cerebral ischemia)
     • Monitor PbtO₂ or jugular venous O₂ sat if available

  6. Repeat Hyperosmolar Boluses
     • Alternate HTS and mannitol if Na⁺ and Osm allow
     • Recheck labs q4h during active titration

═══ TIER 3 — THIRD-LINE / RESCUE THERAPIES ═══
(Refractory ICP despite Tier 1 + 2)

  7. Barbiturate Coma
     ┌─────────────────────────────────────────────┐
     │ Pentobarbital                               │
     │ Load: 5–10 mg/kg IV over 30 min             │
     │ Then: 1–3 mg/kg/hr infusion                 │
     │ Target: EEG burst suppression               │
     │ (3–5 bursts per minute)                     │
     │ Check level q12–24h (target 30–40 mcg/mL)   │
     │ ⚠ Expect hypotension → vasopressors ready   │
     │ ⚠ Immunosuppression risk with prolonged use  │
     └─────────────────────────────────────────────┘
     Alternative: Thiopental 3–5 mg/kg load → 3–5 mg/kg/hr

  8. Decompressive Craniectomy (DC)
     • Unilateral: ≥ 12 × 15 cm (frontotemporoparietal)
     • Bifrontal: per DECRA / RESCUEicp criteria
     • Consider if: age < 60, GCS 4–8, refractory ICP
     • Within 72 hours of injury preferred

  9. Therapeutic Hypothermia (if available)
     • Target 33–35°C core temperature
     • Cooling blanket / intravascular catheter
     • Duration 24–48 hours
     • Rewarm slowly (0.25°C/hr)
     • ⚠ Monitor for coagulopathy, arrhythmia, infection

═══ WEIGHT-BASED QUICK REFERENCE (70 kg Adult) ═══

  Drug                   Dose                  70 kg Example
  ─────────────────────  ────────────────────  ────────────────
  23.4% HTS              0.5–1 mL/kg bolus    35–70 mL
  3% NaCl                150–250 mL bolus     150–250 mL
  Mannitol 20%           0.25–1 g/kg          17.5–70 g
                         (= 1.25–5 mL/kg)     (88–350 mL)
  Propofol               20–75 mcg/kg/min     1.4–5.3 mg/min
  Midazolam              0.02–0.1 mg/kg/hr    1.4–7 mg/hr
  Fentanyl               0.5–2 mcg/kg/hr      35–140 mcg/hr
  Cisatracurium bolus    0.15 mg/kg           10.5 mg
  Cisatracurium gtt      1–3 mcg/kg/min       4.2–12.6 mg/hr
  Pentobarbital load     5–10 mg/kg           350–700 mg
  Pentobarbital gtt      1–3 mg/kg/hr         70–210 mg/hr
  Levetiracetam          500–1000 mg q12h     500–1000 mg

═══ CRRT / HD ADDENDUM ═══
(For patients on Continuous Renal Replacement Therapy
 or Intermittent Hemodialysis)

  General Principles:
  • Mannitol is dialyzable — AVOID in patients on CRRT/HD
    (rapidly cleared → rebound ICP elevation)
  • Hypertonic saline is the preferred osmotic agent in CRRT/HD
  • CRRT may inadvertently lower serum Na⁺ → risk ICP spikes
  • Coordinate Na⁺ management with nephrology daily

  Hypertonic Saline in CRRT/HD:
  • Use 23.4% or 3% NaCl as primary osmotic agent
  • Monitor Na⁺ q4h (more frequently than standard)
  • Request high-sodium replacement fluid (Na⁺ 145–155 mEq/L)
  • Consider Na⁺-enriched dialysate (Na⁺ 150–155 mEq/L)
  • Target serum Na⁺: 150–155 mEq/L in active ICP crisis

  Mannitol Considerations:
  • If mannitol MUST be used → give immediately AFTER HD session
  • In CRRT: mannitol will be cleared continuously → ineffective
  • Osmolar gap monitoring unreliable during CRRT

  Drug Clearance in CRRT/HD:
  ┌───────────────────────────────────────────────────┐
  │ Drug            CRRT Cleared?   HD Cleared?       │
  │ ──────────────  ─────────────   ──────────────    │
  │ Mannitol        Yes (avoid)     Yes (avoid)       │
  │ HTS (NaCl)      Partially*      Partially*        │
  │ Levetiracetam   Yes             Yes               │
  │   → Supplement 250–500 mg after HD session        │
  │   → Increase to 500–1000 mg q8h during CRRT      │
  │ Propofol        No              No                │
  │ Midazolam       No              No                │
  │ Fentanyl        No              No                │
  │ Pentobarbital   No              No                │
  │ Cisatracurium   No (Hofmann)    No                │
  │ Phenytoin       No              No                │
  │ Lacosamide      Yes             Yes               │
  │   → Supplement 50% dose after HD                  │
  └───────────────────────────────────────────────────┘
  * Na⁺ clearance depends on dialysate/replacement fluid Na⁺

  ICP Monitoring During HD:
  • ICP may spike during HD due to osmotic shifts
  • Use slow low-efficiency dialysis (SLED) if possible
  • Pre-treat with 23.4% HTS 30 min before HD session
  • Avoid rapid ultrafiltration (limit < 2 L/session)
  • Consider switching to CRRT if ICP unstable during HD

═══ MONITORING CHECKLIST ═══
  □ ICP waveform quality / transducer level
  □ CPP calculation (MAP – ICP) documented hourly
  □ Serum Na⁺ q4–6h (q4h if on hyperosmolar therapy)
  □ Serum Osm q6–8h (calculate osmolar gap)
  □ ABG q4–6h (PaCO₂ target)
  □ Continuous EEG if on paralytics or barbiturate coma
  □ PbtO₂ > 20 mmHg (if monitored)
  □ Pupillary exam q1h (document size and reactivity)
  □ CT head if ICP refractory or new deficit
  □ Daily labs: BMP, Mg, Phos, CBC, coags, LFTs

═══ REFERENCES ═══
  1. Carney N, et al. Guidelines for the Management of Severe TBI, 4th Ed.
     Brain Trauma Foundation, 2016.
  2. Neurocritical Care Society / ENLS Protocols, 2023.
  3. Harvard Neurosurgery ICP Management Algorithm.
  4. Rabinstein AA. Treatment of Cerebral Edema. Neurologist, 2006.
  5. DECRA Trial — Cooper DJ, et al. NEJM, 2011.
  6. RESCUEicp Trial — Hutchinson PJ, et al. NEJM, 2016.
"""
            ),

            // ── 15. Developmental Milestones (Infants to 5 Years) ───────
            ReferenceItem(
                title: "Developmental Milestones (Infants to 5 Years)",
                category: .guidelines,
                body:
"""
Developmental Milestones — Infants to 5 Years
Based on CDC / AAP 2022 Revised Milestones

═══ 2 MONTHS ═══
  Gross Motor:   Lifts head when on tummy
  Fine Motor:    Hands mostly open (fists relaxing)
  Language:      Coos, makes gurgling sounds
  Cognitive:     Begins to follow objects with eyes
  Social:        First social smile; watches faces closely
  ⚠ Red flags:   No response to loud sounds; does not watch things move;
                 does not smile at people; cannot hold head up on tummy

═══ 4 MONTHS ═══
  Gross Motor:   Holds head steady unsupported; pushes up on elbows on tummy
  Fine Motor:    Reaches for toys with one hand; brings hands to mouth
  Language:      Babbles with expression ("ah-goo"); copies sounds
  Cognitive:     Reaches for a toy; watches faces closely
  Social:        Spontaneous smile; enjoys playing; copies movements
  ⚠ Red flags:   Does not watch things move; no social smile;
                 cannot hold head steady; no cooing or babbling;
                 does not bring things to mouth

═══ 6 MONTHS ═══
  Gross Motor:   Rolls over (both directions); begins to sit without support
  Fine Motor:    Raking grasp; passes objects hand to hand
  Language:      Strings vowels together ("ah", "eh", "oh");
                 responds to own name; makes sounds to show joy/displeasure
  Cognitive:     Brings things to mouth; shows curiosity; tries to get
                 things out of reach
  Social:        Knows familiar faces; likes to play with others;
                 responds to emotions
  ⚠ Red flags:   No reaching for things; no response to sounds;
                 no vowel sounds; does not roll; seems stiff or floppy;
                 no affection for caregivers

═══ 9 MONTHS ═══
  Gross Motor:   Sits without support; pulls to stand; crawls
  Fine Motor:    Pincer grasp developing; picks up small objects
                 between thumb and index finger
  Language:      Understands "no"; makes many different consonant sounds
                 ("mama", "baba", "dada" — non-specific)
  Cognitive:     Watches path of something as it falls; looks for hidden
                 objects (object permanence); plays peek-a-boo
  Social:        May be clingy with familiar adults; has favorite toys;
                 stranger anxiety
  ⚠ Red flags:   Does not bear weight on legs with support; does not sit
                 with help; no babbling ("mama", "baba"); no back-and-forth
                 gestures; does not respond to own name; does not recognize
                 familiar people; does not look where you point

═══ 12 MONTHS ═══
  Gross Motor:   Pulls to stand; cruises along furniture;
                 may take first steps
  Fine Motor:    Neat pincer grasp; puts things in/out of container;
                 releases objects voluntarily
  Language:      1–3 words with meaning ("mama", "dada" — specific);
                 tries to say words you say; uses simple gestures
                 (waving, shaking head)
  Cognitive:     Explores objects (shaking, banging, throwing);
                 finds hidden things; follows simple directions
                 ("pick up the toy")
  Social:        Cries when parent leaves (separation anxiety);
                 shows fear in some situations; hands you a book to read;
                 repeats actions that get attention
  ⚠ Red flags:   Does not crawl; cannot stand with support;
                 no single words; does not point to things;
                 does not learn gestures (wave, shake head);
                 loses skills previously had

═══ 15 MONTHS ═══
  Gross Motor:   Walks independently (most children)
  Fine Motor:    Stacks 2 blocks; scribbles with crayon
  Language:      3–5 words; points to show you something interesting;
                 looks at familiar object when named
  Cognitive:     Explores objects in different ways; copies other children
  Social:        Shows affection; claps when excited; hugs stuffed toy;
                 shows you an object they like
  ⚠ Red flags:   Does not point; does not walk; no words;
                 does not notice when caregiver leaves or returns

═══ 18 MONTHS ═══
  Gross Motor:   Walks independently; may run stiffly; climbs on/off
                 furniture without help
  Fine Motor:    Stacks 3–4 blocks; turns pages of book (2–3 at a time);
                 drinks from cup; eats with spoon (messy)
  Language:      At least 10–20 words; points to show others something
                 interesting; says "no" and shakes head
  Cognitive:     Knows what ordinary things are (phone, brush, spoon);
                 points to get attention; shows interest in a doll by
                 feeding it; points to one body part
  Social:        May have temper tantrums; may be afraid of strangers;
                 shows affection; plays simple pretend (feeding doll);
                 may cling in new situations
  ⚠ Red flags:   Does not point at things; does not walk;
                 fewer than 6 words; does not know familiar objects;
                 does not copy others; does not gain new words;
                 loses skills previously had

═══ 2 YEARS (24 MONTHS) ═══
  Gross Motor:   Kicks a ball; begins to run; walks up stairs with support
  Fine Motor:    Stacks 6+ blocks; turns pages one at a time;
                 turns door handles
  Language:      50+ words; 2-word phrases ("more milk", "mama go");
                 points to things in a book; knows at least 2 body parts
  Cognitive:     Follows 2-step instructions ("pick up toy and put it
                 on the shelf"); beginning make-believe play;
                 sorts shapes and colors
  Social:        Gets excited with other children; shows defiant behavior;
                 plays alongside other children (parallel play);
                 increasing independence
  ⚠ Red flags:   Does not use 2-word phrases (non-echoed);
                 does not know common object functions (phone, brush);
                 does not copy actions or words; does not walk steadily;
                 loses skills previously had

═══ 30 MONTHS ═══
  Gross Motor:   Jumps off the ground with both feet
  Fine Motor:    Turns book pages one at a time; uses hands to twist things
                 (doorknobs, jar lids)
  Language:      Says about 50+ words; 2-word sentences;
                 names items in a picture book ("cat", "dog")
  Cognitive:     Uses things with switches, buttons, or moving parts;
                 plays with more than one toy at a time
  Social:        Plays next to other children; shows you what they can do
                 ("look at me!"); follows simple routines with verbal prompt
  ⚠ Red flags:   Does not use 2-word phrases; does not know what to do
                 with common objects; does not copy actions or words;
                 does not follow simple instructions

═══ 3 YEARS ═══
  Gross Motor:   Climbs well; runs easily; pedals tricycle;
                 walks up/down stairs (one foot per step)
  Fine Motor:    Draws a circle; turns pages one at a time;
                 builds tower of 9+ blocks; turns rotating handles
  Language:      200–1000 words; 3-word sentences; tells you name, age, sex;
                 names familiar friends; strangers can understand most words;
                 carries on a conversation using 2–3 sentences
  Cognitive:     Works 3–4 piece puzzles; copies a circle;
                 turns book pages one at a time; screws/unscrews jar lids;
                 understands "two"; plays make-believe with dolls, animals
  Social:        Takes turns in games; shows concern for crying friend;
                 shows affection for friends without prompting;
                 dresses/undresses self (some help)
  ⚠ Red flags:   Falls a lot or has trouble with stairs;
                 drools or very unclear speech; cannot work simple toys;
                 does not speak in sentences; does not understand simple
                 instructions; does not play pretend;
                 does not want to play with other children or toys;
                 does not make eye contact; loses skills previously had

═══ 4 YEARS ═══
  Gross Motor:   Hops on one foot; catches a bounced ball most of the time;
                 walks up/down stairs without support
  Fine Motor:    Draws a person with 2–4 body parts;
                 uses scissors; begins to copy some capital letters;
                 draws squares and begins to copy
  Language:      Tells stories; speaks in sentences of 5–6 words;
                 says first and last name; uses future tense;
                 sings a song or says a poem from memory
  Cognitive:     Names some colors and numbers; understands counting;
                 begins to understand time; remembers parts of a story;
                 understands "same" and "different"; plays board/card games
  Social:        Enjoys doing new things; plays "Mom" and "Dad";
                 more and more creative with make-believe play;
                 cooperates with other children; talks about likes/interests;
                 difficult to distinguish real from make-believe
  ⚠ Red flags:   Cannot jump in place; has trouble scribbling;
                 no interest in interactive games or make-believe;
                 ignores other children; resists dressing, sleeping, toileting;
                 cannot retell a favorite story; does not follow 3-step
                 instructions; does not understand "same" and "different";
                 does not use "me" and "you" correctly;
                 speech is not understandable to strangers;
                 loses skills previously had

═══ 5 YEARS ═══
  Gross Motor:   Stands on one foot ≥ 10 seconds; hops; may skip;
                 can do a somersault; swings and climbs
  Fine Motor:    Draws a person with ≥ 6 body parts;
                 prints some letters and numbers; copies a triangle;
                 uses fork and spoon; may tie shoes
  Language:      Speaks in sentences of 6+ words; tells a story with
                 full sentences; uses future tense; says name and address;
                 speech fully intelligible
  Cognitive:     Counts 10+ things; draws a person with ≥ 6 parts;
                 prints some letters; copies a triangle;
                 knows about everyday things (money, food, appliances);
                 understands right from left (emerging)
  Social:        Wants to please friends; wants to be like friends;
                 more likely to agree with rules; likes to sing, dance, act;
                 can distinguish real from make-believe;
                 shows more independence; can be demanding and cooperative
  ⚠ Red flags:   Does not show a wide range of emotions;
                 extremely withdrawn; easily distracted; cannot focus
                 on one activity for > 5 minutes; does not respond to people;
                 cannot tell what is real and what is make-believe;
                 does not play a variety of games and activities;
                 cannot give first and last name; does not draw pictures;
                 cannot brush teeth, wash/dry hands, or undress
                 without help; loses skills previously had

═══ PRIMITIVE REFLEXES (Neurology) ═══
  Reflex                  Appears    Disappears
  ─────────────────────   ────────   ──────────
  Moro (startle)          Birth      3–6 months
  Rooting                 Birth      3–4 months
  Sucking                 Birth      3–4 months
  Palmar grasp            Birth      4–6 months
  Plantar grasp           Birth      9–12 months
  ATNR (fencing)          Birth      5–7 months
  Galant (trunk)          Birth      4–6 months
  Stepping / walking      Birth      2 months
  Babinski                Birth      12–24 months
  Landau                  3 months   12–24 months
  Parachute (anterior)    6–9 months Persists

  ⚠ Persistence beyond expected age → suspect upper motor neuron lesion

═══ WHEN TO REFER ═══
  • Any loss of previously acquired skills at ANY age
  • No babbling by 12 months
  • No single words by 16 months
  • No 2-word spontaneous phrases by 24 months
  • No protective reflexes / persistent primitive reflexes
  • Persistent toe-walking after 2 years
  • Head circumference crossing percentiles (up or down)
  • Asymmetric movement or tone at any age
  • Regression in motor, language, or social skills

═══ REFERENCES ═══
  1. CDC / AAP Developmental Milestones — Revised February 2022.
  2. Palpalardi DM. Palpalardi's Palediatric Milestones (Palediatrics Review).
  3. Palpalardi SE, et al. Palediatric Neurology: Principles & Practice, 6th Ed.
  4. AAP Bright Futures: Guidelines for Health Supervision, 4th Ed, 2017.
  5. Gerber RJ, Wilks T, Erdie-Lalena C. Developmental Milestones:
     Motor Development. Pediatr Rev, 2010.
"""
            ),

            // ── 16. Drug Management Protocol for Parkinson's Disease ────
            ReferenceItem(
                title: "Drug Management Protocol for Parkinson's Disease",
                category: .medications,
                body:
"""
Concise Drug Management Protocol for Parkinson's Disease

═══ DIAGNOSIS CONFIRMATION ═══
  Bradykinesia + at least ONE of:
    • Rigidity (lead-pipe / cogwheel)
    • 4–6 Hz resting tremor
  Supportive: unilateral onset, progressive course,
  sustained response to levodopa

═══ WHEN TO START TREATMENT ═══
  • When symptoms cause functional impairment
  • No neuroprotective agent proven — treat symptoms
  • Patient preference and occupation matter

═══ FIRST-LINE THERAPY ═══

  ┌─────────────────────────────────────────────────────────┐
  │ LEVODOPA / CARBIDOPA (Sinemet)                         │
  │ Gold standard — most effective for motor symptoms       │
  │                                                         │
  │ Starting: Carbidopa/Levodopa 25/100 mg TID             │
  │ Titrate: Increase by 100 mg levodopa/day every 3–7 d   │
  │ Usual range: 300–800 mg levodopa/day in 3–4 doses      │
  │ Max: 1500–2000 mg levodopa/day                         │
  │ Take 30 min before meals (protein impairs absorption)   │
  │                                                         │
  │ CR formulation (Sinemet CR 25/100 or 50/200):          │
  │ Useful for nighttime/early morning symptoms             │
  │ Bioavailability ~70% of IR → may need higher dose       │
  │                                                         │
  │ Side effects: nausea, orthostatic hypotension,          │
  │ dyskinesias (long-term), motor fluctuations             │
  └─────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────┐
  │ DOPAMINE AGONISTS                                      │
  │ May be used as monotherapy (younger patients <65)       │
  │ or as adjunct to levodopa                               │
  │                                                         │
  │ Pramipexole (Mirapex):                                 │
  │   Start: 0.125 mg TID                                  │
  │   Titrate: weekly to 0.5–1.5 mg TID                    │
  │   Max: 4.5 mg/day                                      │
  │   ER form: 0.375 mg daily → up to 4.5 mg daily         │
  │                                                         │
  │ Ropinirole (Requip):                                   │
  │   Start: 0.25 mg TID                                   │
  │   Titrate: weekly by 0.25 mg/dose                      │
  │   Usual: 3–8 mg TID                                    │
  │   Max: 24 mg/day                                       │
  │   XL form: 2 mg daily → up to 24 mg daily              │
  │                                                         │
  │ Rotigotine patch (Neupro):                             │
  │   Start: 2 mg/24h patch                                │
  │   Titrate: weekly by 2 mg/24h                          │
  │   Max: 8 mg/24h (early PD), 16 mg/24h (advanced)      │
  │                                                         │
  │ ⚠ Side effects: impulse control disorders (gambling,    │
  │ hypersexuality, binge eating), somnolence, edema,       │
  │ hallucinations (higher risk in elderly),                │
  │ orthostatic hypotension                                 │
  │ ⚠ Avoid abrupt discontinuation → withdrawal syndrome    │
  └─────────────────────────────────────────────────────────┘

═══ ADJUNCT THERAPIES ═══

  ┌─────────────────────────────────────────────────────────┐
  │ MAO-B INHIBITORS                                       │
  │ Mild symptomatic benefit; may delay levodopa need       │
  │                                                         │
  │ Rasagiline (Azilect):                                  │
  │   0.5–1 mg once daily                                  │
  │                                                         │
  │ Selegiline (Eldepryl):                                 │
  │   5 mg BID (morning + noon; avoid evening — insomnia)   │
  │                                                         │
  │ Safinamide (Xadago):                                   │
  │   50–100 mg once daily (adjunct to levodopa)            │
  │                                                         │
  │ ⚠ Serotonin syndrome risk with SSRIs, SNRIs, TCAs,     │
  │ meperidine, tramadol, dextromethorphan                  │
  │ ⚠ Tyramine-rich food caution (less with rasagiline)     │
  └─────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────┐
  │ COMT INHIBITORS                                        │
  │ Extend levodopa duration; reduce "off" time             │
  │ ALWAYS given WITH levodopa                              │
  │                                                         │
  │ Entacapone (Comtan):                                   │
  │   200 mg with each levodopa dose (max 8×/day)          │
  │   Combined form: Stalevo (carbidopa/levodopa/entacapone)│
  │                                                         │
  │ Opicapone (Ongentys):                                  │
  │   50 mg once daily at bedtime                           │
  │   Take on empty stomach; separate from levodopa by 1h   │
  │                                                         │
  │ Tolcapone (Tasmar):                                    │
  │   100 mg TID (adjunct to levodopa)                     │
  │   ⚠ Hepatotoxicity — LFTs q2w × 1yr, then periodically │
  │   Reserved for patients not responding to entacapone     │
  │                                                         │
  │ Side effects: diarrhea, orange urine, dyskinesias       │
  │ (may need to reduce levodopa by 20–30%)                 │
  └─────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────┐
  │ ANTICHOLINERGICS                                       │
  │ Primarily for tremor-dominant PD in younger patients    │
  │                                                         │
  │ Trihexyphenidyl (Artane):                              │
  │   Start: 1 mg daily → titrate to 2 mg TID              │
  │   Max: 15 mg/day                                       │
  │                                                         │
  │ Benztropine (Cogentin):                                │
  │   Start: 0.5 mg daily → up to 2 mg BID                 │
  │                                                         │
  │ ⚠ AVOID in elderly (>65) — cognitive impairment,        │
  │ confusion, hallucinations, urinary retention,           │
  │ constipation, dry mouth, blurred vision                 │
  └─────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────┐
  │ AMANTADINE                                             │
  │ Mild antiparkinsonian effect; primary use: dyskinesia   │
  │                                                         │
  │ Amantadine IR: 100 mg BID–TID                          │
  │ Amantadine ER (Gocovri): 137 mg → 274 mg at bedtime    │
  │ Max: 300 mg/day (IR), 274 mg/day (ER)                  │
  │                                                         │
  │ ⚠ Renal dosing required (CrCl < 50)                    │
  │ ⚠ Livedo reticularis, edema, hallucinations, insomnia   │
  │ ⚠ Avoid abrupt discontinuation → NMS-like syndrome      │
  └─────────────────────────────────────────────────────────┘

═══ MANAGING MOTOR COMPLICATIONS ═══

  "Wearing Off" (end-of-dose deterioration):
  1. Increase levodopa frequency (not dose per se)
  2. Add COMT inhibitor (entacapone or opicapone)
  3. Add MAO-B inhibitor
  4. Switch to CR formulation for trough coverage
  5. Add dopamine agonist

  "On-Off" Fluctuations (unpredictable):
  1. Redistribute protein intake (protein to evening)
  2. Liquid levodopa (dissolve in ascorbic acid water)
  3. Apomorphine SC injection (rescue)
     • Apomorphine 2–6 mg SC PRN (onset 10–20 min)
     • Pre-treat with trimethobenzamide for nausea
  4. Continuous duodenal levodopa infusion (Duopa pump)
  5. Consider deep brain stimulation (DBS)

  Dyskinesias (involuntary movements):
  1. Reduce individual levodopa dose (increase frequency)
  2. Add amantadine (best evidence for dyskinesia)
  3. Reduce/discontinue COMT or MAO-B inhibitor
  4. Consider DBS (STN or GPi target)

═══ NON-MOTOR SYMPTOM MANAGEMENT ═══

  Depression:
  • SSRIs: sertraline, citalopram (first-line)
  • SNRIs: venlafaxine, duloxetine
  • ⚠ Caution combining with MAO-B inhibitors

  Psychosis / Hallucinations:
  • First: reduce anticholinergics → amantadine → dopamine agonists
  • Pimavanserin (Nuplazid) 34 mg daily (first-line for PD psychosis)
  • Quetiapine 12.5–50 mg at bedtime (off-label, commonly used)
  • Clozapine 6.25–50 mg at bedtime (effective but requires CBC monitoring)
  • ⚠ NEVER use typical antipsychotics or risperidone/olanzapine
    (worsen parkinsonism dramatically)

  Dementia:
  • Rivastigmine (Exelon) patch 4.6–13.3 mg/24h (FDA-approved for PDD)
  • Donepezil 5–10 mg daily (off-label)
  • ⚠ May worsen tremor

  Orthostatic Hypotension:
  • Fludrocortisone 0.1–0.3 mg daily
  • Midodrine 2.5–10 mg TID (not after 6 PM)
  • Droxidopa (Northera) 100–600 mg TID
  • Compression stockings, increased salt/fluid intake

  Constipation:
  • Polyethylene glycol (MiraLAX) 17 g daily
  • Lubiprostone 24 mcg BID
  • Exercise, fiber, adequate hydration

  REM Sleep Behavior Disorder:
  • Melatonin 3–12 mg at bedtime (first-line, safest)
  • Clonazepam 0.25–0.5 mg at bedtime (if melatonin fails)
  • Bed safety measures

  Sialorrhea (Drooling):
  • Glycopyrrolate 1 mg BID–TID
  • Botulinum toxin injection to parotid/submandibular glands
  • Atropine 1% sublingual drops

═══ SURGICAL / ADVANCED THERAPIES ═══

  Deep Brain Stimulation (DBS):
  • Candidates: motor fluctuations despite optimized meds,
    ≥ 4 years disease, good levodopa response, no dementia
  • Targets: STN (subthalamic nucleus) or GPi (globus pallidus interna)
  • STN: allows greater medication reduction
  • GPi: better for dyskinesia; less mood side effects

  Levodopa-Carbidopa Intestinal Gel (Duopa):
  • Continuous jejunal infusion via PEG-J tube
  • For advanced PD with severe motor fluctuations
  • Bypasses gastric emptying variability

  Apomorphine Continuous SC Infusion:
  • Pump-delivered; for severe off periods
  • Requires specialist initiation

═══ DRUGS TO AVOID IN PARKINSON'S DISEASE ═══
  ┌───────────────────────────────────────────────────────┐
  │ CONTRAINDICATED (worsen parkinsonism):                │
  │ • Haloperidol, chlorpromazine (typical antipsychotics) │
  │ • Risperidone, olanzapine (atypical but D2 blockade)  │
  │ • Metoclopramide (Reglan) — use domperidone instead   │
  │ • Prochlorperazine (Compazine)                        │
  │ • Droperidol                                          │
  │ • Reserpine, tetrabenazine                            │
  │ • Valproate (may worsen tremor)                       │
  │                                                       │
  │ USE WITH CAUTION:                                     │
  │ • Lithium (may worsen tremor)                         │
  │ • Phenytoin (may worsen ataxia/tremor)                │
  │ • Calcium channel blockers (flunarizine, cinnarizine) │
  └───────────────────────────────────────────────────────┘

═══ HOEHN & YAHR STAGING ═══
  Stage 1:   Unilateral involvement only
  Stage 1.5: Unilateral + axial involvement
  Stage 2:   Bilateral involvement, no balance impairment
  Stage 2.5: Mild bilateral disease with recovery on pull test
  Stage 3:   Bilateral disease; postural instability;
             physically independent
  Stage 4:   Severe disability; still able to walk/stand unassisted
  Stage 5:   Wheelchair-bound or bedridden unless aided

═══ REFERENCES ═══
  1. MDS Evidence-Based Review of Treatments for PD, 2019.
  2. AAN Practice Parameter: Treatment of PD, Updated 2021.
  3. Connolly BS, Lang AE. Pharmacological Treatment of PD:
     A Review. JAMA, 2014.
  4. Fox SH, et al. International PD and MDS Evidence-Based
     Medicine Review. Mov Disord, 2018.
  5. Seppi K, et al. Update on Treatments for Nonmotor Symptoms
     of PD. Mov Disord, 2019.
"""
            ),

        ]
    }
}
