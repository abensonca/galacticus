#!/usr/bin/env python3
import sys
import os
import subprocess
import re
import xml.etree.ElementTree as ET
from datetime import datetime

# Run a suite of benchmarks on the Galacticus code.
# Andrew Benson (21-May-2019; ported to Python)

# Get command line arguments.
if len(sys.argv) != 2:
    print("Usage: benchmark-all.py <statusPath>", file=sys.stderr)
    sys.exit(1)
status_path = sys.argv[1]

# Get current git revision hash.
result = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True)
repo_revision_hash = result.stdout.strip()

# Determine the current repo branch.
result = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True)
repo_branch_name = result.stdout.strip()

# Array of benchmark results.
benchmarks = []

# Open a log file.
log_file = "testSuite/allBenchmarks.log"
os.makedirs("testSuite/benchmark-outputs", exist_ok=True)
subprocess.run("rm -rf testSuite/benchmark-outputs", shell=True)
os.makedirs("testSuite/benchmark-outputs", exist_ok=True)

with open(log_file, "w") as log:
    log.write(":-> Running benchmarks:\n")
    log.write(f"    -> Host:\t{os.environ.get('HOSTNAME', '')}\n")
    log.write(f"    -> Time:\t{datetime.now().strftime('%a %b %e %T %Y')}\n")

# Define benchmarks to run.
benchmarks_to_run = [
    {
        "name":    "stellarLuminosities",
        "compile": "benchmarks.stellar_luminosities.exe",
        "run":     "benchmarks.stellar_luminosities.exe"
    },
    {
        "name":    "quickTest",
        "compile": "Galacticus.exe",
        "run":     "testSuite/benchmarks.quickTest.pl"
    }
]

# Build all benchmarks.
compile_targets = list(set(b["compile"] for b in benchmarks_to_run if "compile" in b))
compile_command = "rm -rf work/build; rm *.exe; make -j16 " + " ".join(sorted(compile_targets))
compile_log = "testSuite/benchmark-outputs/compileBenchmarks.log"

with open(log_file, "a") as log:
    result = subprocess.run(compile_command, shell=True, capture_output=True, text=True)
    with open(compile_log, "w") as cl:
        cl.write(result.stdout)
        cl.write(result.stderr)
    error_status = result.returncode
    job_message = "Benchmark code compilation"

    # Check for failure indicators in compile log.
    with open(compile_log) as cl:
        compile_output = cl.read()
    if error_status == 0 and "FAIL" in compile_output:
        error_status = 1
    if error_status == 0 and "Error:" in compile_output:
        error_status = 1
        job_message = "Compiler errors issued\n" + job_message
    if error_status == 0 and "Warning:" in compile_output:
        error_status = 1
        job_message = "Compiler warnings issued\n" + job_message
    if error_status == 0 and "make:" in compile_output:
        error_status = 1
        job_message = "Make errors issued\n" + job_message

    if error_status == 0:
        log.write(f"SUCCESS: {job_message}\n")
    else:
        log.write(f"FAILED: {job_message}\n")
        log.write("Job output follows:\n")
        log.write(compile_output)
        print(f"FAILED: {job_message}")
        sys.exit(1)

# Run all benchmarks.
with open(log_file, "a") as log:
    for benchmark in benchmarks_to_run:
        label = benchmark["name"]
        bench_log = f"testSuite/benchmark-outputs/{label}.log"
        result = subprocess.run(
            benchmark["run"],
            shell=True,
            capture_output=True,
            text=True
        )
        with open(bench_log, "w") as bl:
            bl.write(result.stdout)
            bl.write(result.stderr)
        bench_output = result.stdout + result.stderr

        if "FAIL" in bench_output:
            log.write(f"FAILED: Benchmark code: {label}\n")
            log.write("Job output follows:\n")
            log.write(bench_output)
        else:
            log.write(f"SUCCESS: Benchmark code: {label}\n")
            # Scan for benchmark results.
            for line in bench_output.splitlines():
                m = re.match(
                    r'^BENCHMARK\s+([a-zA-Z_]+)\s+"([^"]+)"\s+([\d\.]+)\s+([\d\.]+)\s+"([^"]+)"',
                    line
                )
                if m:
                    benchmarks.append({
                        "label":       m.group(1),
                        "description": m.group(2),
                        "time":        m.group(3),
                        "uncertainty": m.group(4),
                        "units":       m.group(5),
                        "hash":        repo_revision_hash,
                        "timestamp":   datetime.now().strftime("%a %b %e %T %Y")
                    })

# Scan log for failures.
fail_lines = []
with open(log_file) as log:
    for line_num, line in enumerate(log, 1):
        if "FAILED" in line or "SKIPPED" in line:
            fail_lines.append(line_num)

exit_status = 0
with open(log_file, "a") as log:
    if not fail_lines:
        log.write("\n\n:-> All benchmarks were successful.\n")
        print("All benchmarks were successful.")
    else:
        log.write("\n\n:-> Failures found. See following lines in log file:\n\t" + "\n\t".join(str(l) for l in fail_lines) + "\n")
        print(f"Failure(s) found - see {log_file} for details.")
        exit_status = 1

# Update benchmarks XML status file.
benchmarks_xml = os.path.join(status_path, "benchmarks.xml")
if os.path.exists(benchmarks_xml):
    tree = ET.parse(benchmarks_xml)
    root = tree.getroot()
    branch_el = root.find(f"galacticus/{repo_branch_name}")
    if branch_el is None:
        galacticus_el = root.find("galacticus")
        if galacticus_el is None:
            galacticus_el = ET.SubElement(root, "galacticus")
        branch_el = ET.SubElement(galacticus_el, repo_branch_name)
    for benchmark in benchmarks:
        label = benchmark.pop("label")
        entry = ET.SubElement(branch_el, label)
        for k, v in benchmark.items():
            entry.set(k, v)
    tree.write(benchmarks_xml)

sys.exit(exit_status)
