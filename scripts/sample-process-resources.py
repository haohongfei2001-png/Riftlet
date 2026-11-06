#!/usr/bin/env python3
"""Read-only macOS process sampling. No launch, signal, tracing or App data access."""
import argparse
import datetime
import json
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pid', type=int, required=True)
parser.add_argument('--seconds', type=int, default=60)
parser.add_argument('--interval', type=float, default=5)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
if args.pid <= 0 or not 1 <= args.seconds <= 3600 or not 0.1 <= args.interval <= 60:
    parser.error('Positive PID, 1..3600 seconds and 0.1..60 second interval required')
# Reserve output before observation; never overwrite an earlier run.
with args.output.open('x') as output:
    def identity():
        return subprocess.check_output(['/bin/ps','-p',str(args.pid),'-o','lstart=','-o','comm='], text=True).strip()
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    clock_start = time.monotonic()
    original = None
    samples, end, status = [], clock_start + args.seconds, 'complete'
    try:
        original = identity()
        while True:
            if identity() != original:
                raise RuntimeError('PID identity changed')
            raw = subprocess.check_output(['/bin/ps','-p',str(args.pid),'-o','%cpu=','-o','rss=','-o','time='], text=True).split()
            samples.append({'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'percentCPU':float(raw[0]),'rssKiB':int(raw[1]),'cumulativeCPU':raw[2]})
            if time.monotonic() >= end:
                break
            time.sleep(min(args.interval, max(0, end-time.monotonic())))
        if identity() != original:
            raise RuntimeError('PID identity changed')
    except (subprocess.SubprocessError, RuntimeError) as error:
        status = 'incomplete:' + type(error).__name__
    json.dump({'scope':'read-only running process observation; activity not controlled; not a leak/idle certification',
        'startedAt':started,'pid':args.pid,'processIdentity':original,
        'requestedSeconds':args.seconds,'elapsedSeconds':time.monotonic()-clock_start,'status':status,'samples':samples}, output, indent=2)
    output.write('\n')
if status != 'complete':
    raise SystemExit(1)
print(json.dumps({'status':status,'samples':len(samples),'minRSSKiB':min(x['rssKiB'] for x in samples),
    'maxRSSKiB':max(x['rssKiB'] for x in samples),'maxPercentCPU':max(x['percentCPU'] for x in samples)}))
