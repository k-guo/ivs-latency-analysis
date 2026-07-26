# NSX IVS Latency Analysis

This repository contains shell scripts used to collect and analyze NSX Industrial vSwitch (IVS) latency statistics for virtual PLC (vPLC) vNIC interfaces.

## Scripts Overview

1. **`ivs_collect_latency_stats_v3.sh`**: A script to run on the ESXi host to collect the IVS latency stats periodically.
2. **`ivs_analyze_lantecy_create_graph.sh`**: A script to run on a jump host or local machine (e.g., macOS/Linux) to parse the collected text files and generate a CSV and graphs.

---

## 1. Data Collection

The `ivs_collect_latency_stats_v3.sh` script is designed to run on the ESXi host where the vPLC is running. It collects latency statistics every 60 seconds and saves them to text files. The script automatically clears the stats every 3 minutes and stops after 3 days.

### Usage

1. Copy `ivs_collect_latency_stats_v3.sh` to the ESXi host.
2. Make the script executable:
   ```bash
   chmod +x ivs_collect_latency_stats_v3.sh
   ```
3. Run the script:
   ```bash
   ./ivs_collect_latency_stats_v3.sh
   ```
   *(You can also run it in the background using `nohup` or `screen` if available).*

4. The script will generate files named `nsx_combined_YYYYMMDD_HHMMSS.txt` in the `/tmp/nsx_stats` directory.

---

## 2. Data Analysis

Once the data collection is complete, export the generated `.txt` files from the ESXi host to your local machine or a jump host.

The `ivs_analyze_lantecy_create_graph.sh` script processes these text files, extracts the relevant latency metrics, and generates visual graphs.

### Usage

1. Place all the collected `nsx_combined_*.txt` files in a single directory.
2. Place `ivs_analyze_lantecy_create_graph.sh` in the same directory.
3. Make the script executable:
   ```bash
   chmod +x ivs_analyze_lantecy_create_graph.sh
   ```
4. Run the script:
   ```bash
   ./ivs_analyze_lantecy_create_graph.sh
   ```

### Output

The analysis script will generate the following files in the same directory:
* **`maxLatency_per_vnic.csv`**: A CSV file containing the parsed latency data.
* **`latency_4_graphs.png`**: An image file containing 4 subplots visualizing the latency over time:
  * Receive Latency
  * Transmit Latency
  * VM Receive Latency
  * Host Polling Ports Max Latency

*Note: The analysis script dynamically generates and executes a Python script (`plot_latency_automated.py`) to create the graphs. It will also create a temporary Python virtual environment (`.nsx_venv`) if the required libraries (`pandas`, `matplotlib`) are not already installed on your system. You do not need to run any Python scripts manually.*
