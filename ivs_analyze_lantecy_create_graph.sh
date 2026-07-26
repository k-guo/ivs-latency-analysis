#!/bin/bash

# Configuration
CSV_FILE="maxLatency_per_vnic.csv"
PY_SCRIPT="plot_latency_automated.py"

echo "================================================="
echo " IVS Latency Analysis Automation"
echo "================================================="

# 1. Check if ANY valid NSX text files exist
count=$(ls -1 nsx_combined_* nsx_ivs_latency_stats_* 2>/dev/null | wc -l)
if [ "$count" -eq 0 ]; then
    echo "❌ Error: No IVS latency data files found."
    echo "Please run this script in the folder containing your 'nsx_ivs_latency_stats_' text files."
    exit 1
fi
echo "✅ Found $count latency log file(s)."

# 2. Extract Data using awk
echo "⏳ Extracting latency data into $CSV_FILE..."
cat nsx_combined_* nsx_ivs_latency_stats_* 2>/dev/null | awk '
  BEGIN {print "Timestamp,PortID,txLatency,rxLatency,vmRxLatency,intrLatency,PollingPortsMax"}
  /CAPTURE TIME:/ {time=$3 " " $4; poll_max="N/A"}
  /Latency histogram/ {in_global=1}
  /maxLatency/ && in_global==1 {poll_max=$3; in_global=0}
  /PortID:/ {port=$2}
  /maxLatency/ && port!="" {
      print time "," port "," $2 "," $3 "," $4 "," $5 "," poll_max;
      port=""
  }
' > "$CSV_FILE"
echo "✅ Data successfully extracted to proper CSV."

# 3. Generate the Python Script dynamically
echo "⏳ Generating Python graphing script..."
cat << 'EOF' > "$PY_SCRIPT"
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

# Read the proper CSV file natively
try:
    df = pd.read_csv("maxLatency_per_vnic.csv")
except Exception as e:
    print(f"❌ Error reading CSV: {e}")
    exit()

if df.empty:
    print("❌ Error: No valid data found to plot.")
    exit()

# Ensure Timestamp is a datetime object
df['Timestamp'] = pd.to_datetime(df['Timestamp'])

ports = df['PortID'].unique()
# Expand to 4 subplots
fig, axes = plt.subplots(4, 1, figsize=(14, 24), sharex=True)

metrics = [
    ('rxLatency', 'Receive Latency (µs)', axes[0]),
    ('txLatency', 'Transmit Latency (µs)', axes[1]),
    ('vmRxLatency', 'VM Receive Latency (µs)', axes[2]),
    ('PollingPortsMax', 'Polling Ports Max Latency (µs)', axes[3])
]

for metric, ylabel, ax in metrics:
    if metric == 'PollingPortsMax':
        # Since PollingPortsMax is a host-level metric, we only need one line
        global_df = df.drop_duplicates(subset=['Timestamp']).sort_values('Timestamp')
        ax.plot(global_df['Timestamp'], global_df[metric], color='purple', linewidth=2.5, label="Host Polling Ports")
    else:
        # Plot individual lines for every vNIC
        for port in ports:
            subset = df[df['PortID'] == port].sort_values("Timestamp")
            ax.plot(subset['Timestamp'], subset[metric], label=f"Port {port}", linewidth=1.5, alpha=0.8)

    ax.set_title(f"{metric} Over Time", fontsize=16)
    ax.set_ylabel(ylabel, fontsize=12)
    ax.grid(True, linestyle='--', alpha=0.6)
    ax.legend(title="Legend", bbox_to_anchor=(1.01, 1), loc='upper left', fontsize='small')

# Explicitly format the X-Axis to ensure seconds are clearly readable
axes[-1].xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m-%d %H:%M:%S'))
axes[-1].set_xlabel("Time", fontsize=14)
axes[-1].tick_params(axis='x', rotation=45)

plt.tight_layout()
plt.savefig("latency_4_graphs.png", dpi=150)
print("✅ Graph saved successfully as latency_4_graphs.png")
EOF

# 4. Handle Python Dependencies cleanly
echo "⏳ Checking Python environment..."
if ! python3 -c "import pandas, matplotlib" 2>/dev/null; then
    echo "   Libraries missing. Creating a temporary virtual environment..."
    python3 -m venv .nsx_venv
    source .nsx_venv/bin/activate
    echo "   Installing pandas and matplotlib (this may take a minute)..."
    pip install pandas matplotlib > /dev/null 2>&1
fi

# 5. Run the Python Script
echo "⏳ Plotting the data..."
python3 "$PY_SCRIPT"

# Clean up virtual environment if we used it
if [ -n "$VIRTUAL_ENV" ]; then
    deactivate
fi

echo "================================================="
echo " 🎉 Analysis Complete!"
echo " 📁 Output Data:  $CSV_FILE"
echo " 📊 Output Graph: latency_4_graphs.png"
echo "================================================="