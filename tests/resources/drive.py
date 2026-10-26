"""Run one function of tests/resources/testing.py in a fresh interpreter.

  python3 -I tests/resources/drive.py <scripts dir> <function>      JSON args on stdin, JSON result on stdout

A subprocess driver instead of a pickled seam: the bundle's modules register themselves in
sys.modules, so each scripts directory (the real one, a mutated copy, a launcher copy) gets
a process of its own, and concurrent cases never share interpreter state.
"""
import importlib.util
import json
import os
import sys


def main(argv):
    sys.dont_write_bytecode = True  # never leave a .pyc beside the fixtures or the scripts under test
    os.umask(0)  # modes in the scripts must be explicit, not an accident of the caller's umask
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("testing", os.path.join(here, "testing.py"))
    testing = importlib.util.module_from_spec(spec)
    sys.modules["testing"] = testing
    spec.loader.exec_module(testing)
    scripts, name = argv
    result = getattr(testing, name)(scripts, json.load(sys.stdin))
    json.dump(result, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
