#!/usr/bin/env python3
import subprocess
import sys
import os
import glob

# Run a set of short Galacticus models which test cases that have failed before,
# in order to catch regressions.
# Andrew Benson (ported to Python)

# Indicate that this test can manage its own jobs.
# selfManage: true

outputDirectory = "outputs/regressions"
subprocess.run(f"mkdir -p {outputDirectory}", shell=True)

# Find all regression parameter files and run them.
overallStatus = "SUCCESS"
for filePath in sorted(glob.glob("regressions/**/*.xml", recursive=True) + glob.glob("regressions/**/*.py", recursive=True)):
    if filePath.endswith(".xml"):
        print(f"Running regression: {filePath}")
        subprocess.run(f"mkdir -p {outputDirectory}/{os.path.basename(filePath).replace('.xml', '')}", shell=True)
        with open(f"{outputDirectory}/{os.path.basename(filePath).replace('.xml', '')}.log", "w") as logFile:
            status = subprocess.run(
                f"cd ..; ./Galacticus.exe testSuite/{filePath}",
                shell=True, stdout=logFile, stderr=subprocess.STDOUT
            )
        logFilePath = f"{outputDirectory}/{os.path.basename(filePath).replace('.xml', '')}.log"
        result = subprocess.run(f"grep -q -i -e fatal -e aborted {logFilePath}", shell=True)
        if result.returncode == 0 or status.returncode != 0:
            print(f"FAILED: regression '{filePath}'")
            with open(logFilePath) as f:
                print(f.read())
            overallStatus = "FAILED"
        else:
            print(f"SUCCESS: regression '{filePath}'")
    elif filePath.endswith(".py"):
        print(f"Running regression script: {filePath}")
        status = subprocess.run(f"cd testSuite; python3 {filePath}", shell=True)
        if status.returncode != 0:
            print(f"FAILED: regression script '{filePath}'")
            overallStatus = "FAILED"
        else:
            print(f"SUCCESS: regression script '{filePath}'")

print(f"{overallStatus}: regressions")
