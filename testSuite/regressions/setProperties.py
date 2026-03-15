#!/usr/bin/env python3
import subprocess
import sys
import h5py

# Run a test case for setting properties back to the HDF5 output file.
# Andrew Benson (15-October-2014; ported to Python)

# Run the model and check for successful completion.
status = subprocess.run("./Galacticus.exe testSuite/parameters/setProperties.xml", shell=True)
if status.returncode != 0:
    print("FAILED: setProperties model failed to complete")
    sys.exit(1)

# Check that the inclination property was written to the HDF5 output file.
try:
    with h5py.File("testSuite/outputs/test-set-properties.hdf5", "r") as model:
        output = model["Outputs"]
        # Find the output at z=0 and check for the inclination dataset.
        found = False
        for output_name in output:
            node_data = output[output_name].get("nodeData")
            if node_data is not None and "inclination" in node_data:
                found = True
                break
        if not found:
            print("FAILED: setProperties: unable to set property in HDF5 file")
            sys.exit(1)
except Exception as e:
    print(f"FAILED: setProperties: unable to set property in HDF5 file ({e})")
    sys.exit(1)

print("SUCCESS: setProperties")
