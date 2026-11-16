"""Simulate the native setup protocol without accounts, downloads or game data"""
import json
import signal
import sys
import time


def emit(state, title, detail='', progress=None):
    print(json.dumps({'state': state, 'title': title, 'detail': detail, 'progress': progress}), flush=True)


def cancel(*_args):
    emit('cancelled', 'Preview paused', 'No accounts or game files were accessed')
    raise SystemExit(0)


def main():
    signal.signal(signal.SIGTERM, cancel)
    if any(flag in sys.argv for flag in ('--status', '--warmup', '--sign-out')):
        emit('new', 'Minecraft on your Mac')
        return
    detail = 'Interface preview only — no sign-in, download or game launch'
    emit('busy', 'Sign in to Microsoft', detail, 0.2)
    time.sleep(2)
    for step in range(41):
        emit('busy', 'Downloading Minecraft', detail, 0.35 + step / 80)
        time.sleep(0.2)
    emit('busy', 'Preparing Minecraft', detail, 0.9)
    time.sleep(1)
    emit('busy', 'Finishing setup', detail, 0.95)
    time.sleep(1)
    emit('playing', 'Minecraft is running', detail)
    time.sleep(3)
    emit('ready', 'Ready to play', 'Preview complete — no accounts or game files were accessed')


if __name__ == '__main__':
    main()
