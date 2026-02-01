#!/bin/bash
# Setup and launch the EEG Analysis Server for Neuro EMR
# Prerequisites: Python 3.8+ must be installed

set -e

echo "=== Neuro EMR — EEG Analysis Server Setup ==="
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "ERROR: python3 not found. Please install Python 3.8+."
    exit 1
fi

echo "Python: $(python3 --version)"

# Install dependencies
echo ""
echo "Installing dependencies..."
pip3 install --quiet flask mne numpy scipy

echo ""
echo "Dependencies installed successfully."
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Launch server
echo "Starting EEG Analysis Server on http://localhost:5050 ..."
echo "Press Ctrl+C to stop."
echo ""
python3 "$SCRIPT_DIR/eeg_server.py"
