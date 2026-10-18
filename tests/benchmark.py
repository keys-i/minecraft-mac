#!/usr/bin/env python3
"""Measure helper handoff with a local fixture, without Microsoft or Keychain"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import statistics
import sys
import tempfile
import time


def measure(source):
    spec = importlib.util.spec_from_file_location('runtime_benchmark', source)
    runtime = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runtime)
    samples, lookups = [], []
    for _ in range(7):
        with tempfile.TemporaryDirectory(prefix='mc-') as temporary:
            root = Path(temporary)
            helper, endpoint = root / 'helper.py', root / 'account.sock'
            helper.write_text(
                'import os, signal, socket, sys, time\n'
                'signal.signal(signal.SIGINT, lambda *_: sys.exit(0))\n'
                'time.sleep(0.08)\n'
                'connection = socket.socket(socket.AF_UNIX)\n'
                f'connection.bind({str(endpoint)!r})\n'
                f'os.chmod({str(endpoint)!r}, 0o600)\n'
                'connection.listen(1)\n'
                'signal.pause()\n')
            runtime.ROOT, runtime.HELPER = root, helper
            runtime.STATE, runtime.SOCKET = root / 'session.json', endpoint
            calls = 0

            def account_pid():
                nonlocal calls
                calls += 1
                if not runtime.STATE.exists():
                    return None
                pid = json.loads(runtime.STATE.read_text())['pid']
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    return None
                return pid

            runtime.account_pid = account_pid
            popen = runtime.subprocess.Popen

            def spawn(command, **kwargs):
                assert command[0] == str(helper.resolve())
                return popen([sys.executable, *command], **kwargs)

            runtime.subprocess.Popen = spawn
            try:
                start = time.perf_counter()
                with runtime.account(root, progress=lambda _: None, timeout=5):
                    samples.append((time.perf_counter() - start) * 1000)
                    lookups.append(calls)
                    assert endpoint.is_socket()
            finally:
                runtime.subprocess.Popen = popen
            assert not endpoint.exists(), 'The fixture left its socket behind'
    return {'median_ms': round(statistics.median(samples), 3),
            'samples_ms': [round(value, 3) for value in samples],
            'owner_lookups': lookups}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runtime', type=Path, nargs='?',
                        default=Path(__file__).resolve().parents[1] / 'src/standalone.py')
    args = parser.parse_args()
    print(json.dumps(measure(args.runtime.resolve()), indent=2))
