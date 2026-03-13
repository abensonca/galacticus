#!/usr/bin/env python3
import sys
import os
import stat
import subprocess
import threading

# A simple wrapper script which launches multiple threads to process the input list of scripts.
# Andrew Benson (31-May-2016)

tasks = list(sys.argv[1:])
threads = []


def run_script(script_file, log_file):
    # Ensure the script is executable (chmod u+x).
    current_mode = os.stat(script_file).st_mode
    os.chmod(script_file, current_mode | stat.S_IXUSR)
    with open(log_file, 'w') as log:
        subprocess.run(script_file, shell=True, stdout=log, stderr=subprocess.STDOUT)


while tasks:
    script_file = tasks.pop(0)
    log_file    = tasks.pop(0)
    t = threading.Thread(target=run_script, args=(script_file, log_file))
    threads.append(t)
    t.start()

for t in threads:
    t.join()
