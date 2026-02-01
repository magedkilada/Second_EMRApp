#!/usr/bin/env python3
"""
EEG Analysis Server for Neuro EMR
Runs on localhost:5050, accepts EEG file uploads, processes with MNE-Python.
"""

import os
import sys
import json
import tempfile
import traceback
import numpy as np
from flask import Flask, request, jsonify

try:
    import mne
    mne.set_log_level("WARNING")
except ImportError:
    print("ERROR: MNE-Python not installed. Run: pip3 install mne")
    sys.exit(1)

app = Flask(__name__)

# Map file extensions to MNE reader functions
READERS = {
    ".edf": mne.io.read_raw_edf,
    ".bdf": mne.io.read_raw_bdf,
    ".gdf": mne.io.read_raw_gdf,
    ".fif": mne.io.read_raw_fif,
    ".vhdr": mne.io.read_raw_brainvision,
    ".set": mne.io.read_raw_eeglab,
    ".cnt": mne.io.read_raw_cnt,
    ".eeg": mne.io.read_raw_nihon,  # Nihon Kohden .eeg
}

BAND_RANGES = {
    "Delta (0.5-4 Hz)": (0.5, 4),
    "Theta (4-8 Hz)": (4, 8),
    "Alpha (8-13 Hz)": (8, 13),
    "Beta (13-30 Hz)": (13, 30),
    "Gamma (30-45 Hz)": (30, 45),
}


def compute_band_powers(raw):
    """Compute average power in standard EEG frequency bands."""
    sfreq = raw.info["sfreq"]
    data = raw.get_data()  # (n_channels, n_samples)

    from scipy.signal import welch

    band_powers = {}
    for band_name, (fmin, fmax) in BAND_RANGES.items():
        powers = []
        for ch_idx in range(data.shape[0]):
            freqs, psd = welch(data[ch_idx], fs=sfreq, nperseg=min(int(sfreq * 2), data.shape[1]))
            idx_band = np.logical_and(freqs >= fmin, freqs <= fmax)
            if idx_band.any():
                powers.append(np.mean(psd[idx_band]))
            else:
                powers.append(0.0)
        band_powers[band_name] = float(np.mean(powers))

    # Normalize to percentages
    total = sum(band_powers.values())
    if total > 0:
        band_pct = {k: round(v / total * 100, 1) for k, v in band_powers.items()}
    else:
        band_pct = {k: 0.0 for k in band_powers}

    return band_powers, band_pct


def detect_artifacts(raw, threshold_uv=200):
    """Simple artifact detection: epochs with amplitude > threshold."""
    data = raw.get_data() * 1e6  # Convert to microvolts
    epoch_len = int(raw.info["sfreq"])  # 1-second epochs
    n_epochs = data.shape[1] // epoch_len
    artifact_count = 0

    for i in range(n_epochs):
        segment = data[:, i * epoch_len : (i + 1) * epoch_len]
        peak = np.max(np.abs(segment))
        if peak > threshold_uv:
            artifact_count += 1

    return artifact_count, n_epochs


def analyze_eeg(filepath):
    """Run full EEG analysis pipeline on a file."""
    ext = os.path.splitext(filepath)[1].lower()
    reader = READERS.get(ext)
    if reader is None:
        return None, f"Unsupported file format: {ext}. Supported: {', '.join(READERS.keys())}"

    raw = reader(filepath, preload=True)

    # Basic info
    n_channels = len(raw.ch_names)
    duration_sec = raw.times[-1]
    sfreq = raw.info["sfreq"]
    channels = raw.ch_names

    # Channel types
    ch_types = {}
    for ch in raw.info["chs"]:
        t = mne.channel_type(raw.info, raw.ch_names.index(ch["ch_name"]))
        ch_types.setdefault(t, []).append(ch["ch_name"])

    # Filter for analysis (0.5-45 Hz bandpass)
    raw_filtered = raw.copy().filter(l_freq=0.5, h_freq=45.0, verbose=False)

    # Band powers
    band_powers_raw, band_pct = compute_band_powers(raw_filtered)

    # Amplitude statistics (in microvolts)
    data_uv = raw_filtered.get_data() * 1e6
    amp_stats = {
        "mean_uv": round(float(np.mean(np.abs(data_uv))), 2),
        "max_uv": round(float(np.max(np.abs(data_uv))), 2),
        "std_uv": round(float(np.std(data_uv)), 2),
    }

    # Artifact detection
    artifact_count, total_epochs = detect_artifacts(raw_filtered)

    # Events
    try:
        events = mne.find_events(raw, verbose=False)
        n_events = len(events)
        event_ids = list(set(events[:, 2].tolist())) if n_events > 0 else []
    except Exception:
        n_events = 0
        event_ids = []

    # Build clinical report
    report_lines = []
    report_lines.append("=" * 60)
    report_lines.append("EEG ANALYSIS REPORT (MNE-Python)")
    report_lines.append("=" * 60)
    report_lines.append("")
    report_lines.append("RECORDING PARAMETERS:")
    report_lines.append(f"  Channels: {n_channels}")
    report_lines.append(f"  Duration: {duration_sec:.1f} seconds ({duration_sec/60:.1f} minutes)")
    report_lines.append(f"  Sampling Rate: {sfreq:.1f} Hz")

    if ch_types:
        report_lines.append(f"  Channel Types: {', '.join(f'{k} ({len(v)})' for k, v in ch_types.items())}")

    report_lines.append(f"  Channel Names: {', '.join(channels[:20])}")
    if n_channels > 20:
        report_lines.append(f"    ... and {n_channels - 20} more")

    report_lines.append("")
    report_lines.append("FREQUENCY BAND ANALYSIS (0.5-45 Hz bandpass):")

    # Determine dominant band
    dominant_band = max(band_pct, key=band_pct.get)
    for band_name, pct in band_pct.items():
        marker = " <<<" if band_name == dominant_band else ""
        bar = "#" * int(pct / 2)
        report_lines.append(f"  {band_name:25s} {pct:5.1f}%  {bar}{marker}")

    report_lines.append(f"\n  Dominant rhythm: {dominant_band}")

    # Clinical interpretation of dominant rhythm
    report_lines.append("")
    report_lines.append("BACKGROUND ACTIVITY:")
    if "Alpha" in dominant_band:
        report_lines.append("  Posterior dominant rhythm is in the alpha range, suggesting")
        report_lines.append("  a normal awake background for an adult.")
    elif "Theta" in dominant_band:
        report_lines.append("  Dominant theta activity noted. This may indicate drowsiness,")
        report_lines.append("  encephalopathy, or may be normal in younger patients.")
    elif "Delta" in dominant_band:
        report_lines.append("  Dominant delta activity noted. This may indicate deep sleep,")
        report_lines.append("  sedation, or diffuse cerebral dysfunction.")
    elif "Beta" in dominant_band:
        report_lines.append("  Dominant beta activity noted. This may be related to")
        report_lines.append("  medication effect (e.g., benzodiazepines) or anxiety state.")
    elif "Gamma" in dominant_band:
        report_lines.append("  Elevated gamma activity noted. Consider muscle artifact")
        report_lines.append("  or active cognitive processing.")

    report_lines.append("")
    report_lines.append("AMPLITUDE STATISTICS:")
    report_lines.append(f"  Mean: {amp_stats['mean_uv']:.1f} µV")
    report_lines.append(f"  Max:  {amp_stats['max_uv']:.1f} µV")
    report_lines.append(f"  Std:  {amp_stats['std_uv']:.1f} µV")

    report_lines.append("")
    report_lines.append("ARTIFACT DETECTION:")
    if total_epochs > 0:
        pct_artifact = artifact_count / total_epochs * 100
        report_lines.append(f"  High-amplitude epochs (>200 µV): {artifact_count}/{total_epochs} ({pct_artifact:.1f}%)")
        if pct_artifact > 30:
            report_lines.append("  NOTE: High artifact burden. Consider re-recording or artifact rejection.")
        elif pct_artifact > 10:
            report_lines.append("  NOTE: Moderate artifact contamination detected.")
        else:
            report_lines.append("  Artifact burden is within acceptable limits.")
    else:
        report_lines.append("  Unable to compute (recording too short).")

    if n_events > 0:
        report_lines.append("")
        report_lines.append("EVENT MARKERS:")
        report_lines.append(f"  Total events: {n_events}")
        report_lines.append(f"  Unique event IDs: {event_ids}")

    report_lines.append("")
    report_lines.append("=" * 60)
    report_lines.append("DISCLAIMER: This is an automated analysis. All findings must")
    report_lines.append("be reviewed and interpreted by a qualified neurologist.")
    report_lines.append("=" * 60)

    report_text = "\n".join(report_lines)

    result = {
        "report": report_text,
        "channels": channels,
        "n_channels": n_channels,
        "duration_sec": round(duration_sec, 2),
        "sampling_rate": sfreq,
        "bands": band_pct,
        "dominant_band": dominant_band,
        "amplitude": amp_stats,
        "artifacts": {
            "count": artifact_count,
            "total_epochs": total_epochs,
        },
        "events": n_events,
    }

    return result, None


@app.route("/analyze", methods=["POST"])
def analyze():
    if "file" not in request.files:
        return jsonify({"error": "No file uploaded. Send a multipart POST with a 'file' field."}), 400

    uploaded = request.files["file"]
    if uploaded.filename == "":
        return jsonify({"error": "Empty filename."}), 400

    ext = os.path.splitext(uploaded.filename)[1].lower()
    if ext not in READERS:
        return jsonify({
            "error": f"Unsupported format: {ext}. Supported: {', '.join(READERS.keys())}"
        }), 400

    # Save to temp file preserving extension
    with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
        uploaded.save(tmp)
        tmp_path = tmp.name

    try:
        result, error = analyze_eeg(tmp_path)
        if error:
            return jsonify({"error": error}), 422
        return jsonify(result)
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": f"Analysis failed: {str(e)}"}), 500
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "mne_version": mne.__version__,
        "supported_formats": list(READERS.keys()),
    })


if __name__ == "__main__":
    print(f"EEG Analysis Server starting on http://localhost:5050")
    print(f"MNE-Python version: {mne.__version__}")
    print(f"Supported formats: {', '.join(READERS.keys())}")
    print()
    app.run(host="127.0.0.1", port=5050, debug=False)
