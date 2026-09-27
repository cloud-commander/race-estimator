#!/usr/bin/env python3
"""Convert a Garmin .fit activity into a replay fixture for the unit tests.

    python3 tools/fit_to_replay.py path/to/activity.fit [--every 5]

Writes test/ReplayData.mc: timer seconds, distance (m) and altitude (m)
sampled every N seconds of timer time (pauses removed). No GPS coordinates,
heart rate or timestamps are kept, only what the pace model sees.

Self-contained FIT decoder (no fitparse): reads definition and data
messages, compressed-timestamp headers and developer fields, and extracts
`record` (distance, altitude / enhanced_altitude, timestamp) and `event`
(timer start/stop) messages.
"""
import argparse
import os
import struct
import sys

MESG_RECORD = 20
MESG_EVENT = 21
EVENT_TIMER = 0
EVENT_TYPE_START = 0
EVENT_TYPE_STOP_ALL = 4
EVENT_TYPE_STOP = 1

BASE_FMT = {  # base type number & 0x1F -> (struct fmt, size)
    0x00: ("B", 1), 0x01: ("b", 1), 0x02: ("B", 1), 0x03: ("h", 2),
    0x04: ("H", 2), 0x05: ("i", 4), 0x06: ("I", 4), 0x07: ("s", 1),
    0x08: ("f", 4), 0x09: ("d", 8), 0x0A: ("B", 1), 0x0B: ("H", 2),
    0x0C: ("I", 4), 0x0D: ("B", 1), 0x0E: ("q", 8), 0x0F: ("Q", 8),
    0x10: ("Q", 8),
}
INVALID = {"B": 0xFF, "b": 0x7F, "h": 0x7FFF, "H": 0xFFFF, "i": 0x7FFFFFFF,
           "I": 0xFFFFFFFF, "q": 0x7FFFFFFFFFFFFFFF, "Q": 0xFFFFFFFFFFFFFFFF}


def decode(path):
    """Yield (global_mesg_num, {field_num: value}) for every data message."""
    data = open(path, "rb").read()
    header_size = data[0]
    data_size = struct.unpack_from("<I", data, 4)[0]
    if data[8:12] != b".FIT":
        raise ValueError("not a FIT file")
    pos = header_size
    end = header_size + data_size
    defs = {}
    last_ts = None
    while pos < end:
        h = data[pos]
        pos += 1
        if h & 0x80:  # compressed timestamp data message
            local = (h >> 5) & 0x03
            offset = h & 0x1F
            if last_ts is not None:
                ts = (last_ts & ~0x1F) + offset
                if offset < (last_ts & 0x1F):
                    ts += 0x20
                last_ts = ts
            d = defs[local]
            fields, pos = read_fields(data, pos, d)
            if last_ts is not None:
                fields.setdefault(253, last_ts)
            yield d["global"], fields
            continue
        local = h & 0x0F
        if h & 0x40:  # definition
            has_dev = bool(h & 0x20)
            arch = data[pos + 1]
            endian = ">" if arch == 1 else "<"
            glob = struct.unpack_from(endian + "H", data, pos + 2)[0]
            nfields = data[pos + 4]
            pos += 5
            fields = []
            for _ in range(nfields):
                num, size, base = data[pos], data[pos + 1], data[pos + 2]
                fields.append((num, size, base & 0x1F))
                pos += 3
            dev_size = 0
            if has_dev:
                ndev = data[pos]
                pos += 1
                for _ in range(ndev):
                    dev_size += data[pos + 1]
                    pos += 3
            defs[local] = {"global": glob, "endian": endian,
                           "fields": fields, "dev": dev_size}
        else:
            d = defs[local]
            fields, pos = read_fields(data, pos, d)
            if 253 in fields:
                last_ts = fields[253]
            yield d["global"], fields


def read_fields(data, pos, d):
    out = {}
    for num, size, base in d["fields"]:
        fmt, bsize = BASE_FMT.get(base, ("B", 1))
        raw = data[pos:pos + size]
        pos += size
        if fmt == "s" or size != bsize:
            continue  # strings and arrays: not needed
        val = struct.unpack(d["endian"] + fmt, raw)[0]
        if fmt in INVALID and val == INVALID[fmt]:
            continue
        out[num] = val
    pos += d["dev"]
    return out, pos


def extract(path):
    """Return [(timer_sec, distance_m, altitude_m or None)] per record."""
    rows = []
    running = True
    timer = 0.0
    last_ts = None
    for glob, f in decode(path):
        if glob == MESG_EVENT and f.get(0) == EVENT_TIMER:
            etype = f.get(1)
            if etype in (EVENT_TYPE_STOP, EVENT_TYPE_STOP_ALL):
                running = False
            elif etype == EVENT_TYPE_START:
                running = True
                last_ts = f.get(253, last_ts)
            continue
        if glob != MESG_RECORD or 253 not in f or 5 not in f:
            continue
        ts = f[253]
        if running and last_ts is not None:
            timer += max(0, ts - last_ts)
        last_ts = ts
        if not running:
            continue
        dist = f[5] / 100.0
        alt = None
        if 78 in f:
            alt = f[78] / 5.0 - 500.0
        elif 2 in f:
            alt = f[2] / 5.0 - 500.0
        rows.append((timer, dist, alt))
    return rows


def resample(rows, every):
    out = []
    next_t = every
    last_alt = next((r[2] for r in rows if r[2] is not None), 0.0)
    for t, d, a in rows:
        if a is not None:
            last_alt = a
        if t >= next_t and d > 0:
            out.append((t, d, last_alt))
            next_t = t + every
    return out


def write_fixture(samples, source, dest):
    # Space-separated integers (large array literals overflow the Monkey C
    # type checker); ReplayHelper parses them once at test time.
    def packed(vals):
        return '    "%s"' % " ".join(str(int(round(v))) for v in vals)

    t = [s[0] for s in samples]
    d = [s[1] * 10 for s in samples]  # decimetres
    a = [s[2] * 10 for s in samples]
    km = samples[-1][1] / 1000.0
    mins = t[-1] / 60.0
    body = f"""using Toybox.Lang;

// GENERATED by tools/fit_to_replay.py from {os.path.basename(source)}
// {len(samples)} samples, {km:.2f} km in {mins:.1f} min of timer time.
// Only timer time, distance and altitude: no position or other data.
// Space-separated integers: seconds, decimetres, decimetres.
(:test)
module ReplayData {{
  const TIMER_SEC =
{packed(t)};
  const DISTANCE_DM =
{packed(d)};
  const ALTITUDE_DM =
{packed(a)};
}}
"""
    open(dest, "w").write(body)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("fit")
    ap.add_argument("--every", type=float, default=5.0, help="seconds between samples")
    ap.add_argument("--out", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "test", "ReplayData.mc"))
    args = ap.parse_args()
    rows = extract(args.fit)
    if len(rows) < 10:
        sys.exit("no distance records found")
    samples = resample(rows, args.every)
    write_fixture(samples, args.fit, args.out)
    alts = [s[2] for s in samples]
    print(f"{len(samples)} samples, {samples[-1][1]/1000:.2f} km, "
          f"{samples[-1][0]/60:.1f} min, altitude {min(alts):.0f}-{max(alts):.0f} m "
          f"-> {os.path.relpath(args.out)}")


if __name__ == "__main__":
    main()
