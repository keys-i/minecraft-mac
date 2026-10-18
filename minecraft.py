#!/usr/bin/env python3
"""Build, inspect and run Minecraft for MacOS from one entry point"""
import argparse
from pathlib import Path
import runpy
import sys

ROOT = Path(__file__).resolve().parent
COMMANDS = {
    'build': 'tools/build.py',
    'source': 'tools/source.py',
    'play': 'tools/setup.py',
    'runtime': 'src/standalone.py',
    'monitor': 'tools/monitor.py',
    'legacy': 'tools/legacy/launch.py',
}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=COMMANDS, help='Use COMMAND --help for its arguments')
    args = parser.parse_args(argv[:1])
    script = ROOT / COMMANDS[args.command]
    previous = sys.argv
    try:
        sys.argv = [str(script), *argv[1:]]
        sys.dont_write_bytecode = True
        runpy.run_path(str(script), run_name='__main__')
    finally:
        sys.argv = previous


if __name__ == '__main__':
    main()
