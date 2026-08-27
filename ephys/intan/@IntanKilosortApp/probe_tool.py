"""probe_tool.py -- probeinterface front-door for IntanKilosortApp.

Builds Kilosort4 probe .json files (chanMap / xc / yc / kcoords / n_chan / notes)
from the probeinterface library or from parametric generators. probeinterface is
used *only* here: the app stores and the sorting pipeline consumes plain KS4 JSON,
so this script converts a probeinterface Probe into that schema on the way out
(the exact inverse of run_si_ks4.build_probe).

Invoked by @IntanKilosortApp/runProbeTool.m through the same env python /
`conda run` mechanism as run_ks4.py / run_si_ks4.py. All results are emitted as
JSON on stdout (list-library, describe) or written to <out.json> (get-library,
generate); a leading "PROBE_TOOL_ERROR" line + non-zero exit signals failure.

Usage:
  probe_tool.py list-library [--tag TAG]
  probe_tool.py get-library <manufacturer> <probe_name> <out.json>
                            [--name N] [--notes S] [--wiring w0,w1,...] [--n-chan K]
  probe_tool.py generate <spec.json> <out.json>
  probe_tool.py describe <in.json>
"""
import sys
import os
import json
import traceback


def _np():
    import numpy as np
    return np


# --------------------------------------------------------------------------
# probeinterface Probe -> Kilosort4 dict (inverse of run_si_ks4.build_probe)
# --------------------------------------------------------------------------
def pi_probe_to_ks4(probe, n_chan=None, wiring=None, name=None, notes=None):
    np = _np()
    pos = np.asarray(probe.contact_positions, dtype=float)
    n = pos.shape[0]
    xc = pos[:, 0]
    yc = pos[:, 1] if pos.shape[1] > 1 else np.zeros(n)

    # shank_ids (strings in probeinterface) -> integer kcoords, groups preserved
    sh = getattr(probe, 'shank_ids', None)
    if sh is not None and len(sh) == n:
        uniq = list(dict.fromkeys(str(s) for s in sh))
        idx = {u: i for i, u in enumerate(uniq)}
        kcoords = [idx[str(s)] for s in sh]
    else:
        kcoords = [0] * n

    # chanMap: explicit wiring > probe.device_channel_indices > identity
    if wiring is not None:
        chan_map = [int(v) for v in wiring]
    else:
        dci = getattr(probe, 'device_channel_indices', None)
        if dci is not None and len(dci) == n and not np.any(np.asarray(dci) < 0):
            chan_map = [int(v) for v in dci]
        else:
            chan_map = list(range(n))

    if len(chan_map) != n:
        raise ValueError('wiring length %d != contact count %d' % (len(chan_map), n))

    if n_chan is None:
        n_chan = max(n, (max(chan_map) + 1) if chan_map else n)

    return {
        'notes': notes if notes is not None else _annotation_notes(probe, name),
        'chanMap': [int(v) for v in chan_map],
        'xc': [_round(v) for v in xc],
        'yc': [_round(v) for v in yc],
        'kcoords': [int(v) for v in kcoords],
        'n_chan': int(n_chan),
    }


def _round(v):
    r = round(float(v), 4)
    return int(r) if r == int(r) else r


def _annotation_notes(probe, name=None):
    ann = getattr(probe, 'annotations', {}) or {}
    parts = []
    man = ann.get('manufacturer')
    nm = name or ann.get('name') or ann.get('model_name')
    if man:
        parts.append(str(man))
    if nm:
        parts.append(str(nm))
    return ' '.join(parts)


def _write_ks4(d, out_path):
    with open(out_path, 'w') as f:
        json.dump(d, f, indent=2)


# --------------------------------------------------------------------------
# subcommands
# --------------------------------------------------------------------------
def cmd_list_library(args):
    # Emit an ARRAY of {manufacturer, probes} so MATLAB jsondecode preserves the
    # exact manufacturer strings (some contain hyphens, which are not valid
    # struct field names if the payload were an object keyed by manufacturer).
    tag = _opt(args, '--tag')
    entries = {}
    try:
        from probeinterface.library import (
            list_manufacturers, list_probes_by_manufacturer)
        mans = list_manufacturers(tag=tag) if tag else list_manufacturers()
        for m in mans:
            try:
                probes = list_probes_by_manufacturer(m, tag=tag) if tag \
                    else list_probes_by_manufacturer(m)
                entries[str(m)] = sorted(str(p) for p in probes)
            except Exception:
                entries[str(m)] = []
    except Exception:
        # Older/newer probeinterface without the listing helpers: hand back the
        # known manufacturers so the UI can still offer them (probe names typed).
        entries = {'neuronexus': [], 'cambridgeneurotech': [], 'plexon': []}
    result = [{'manufacturer': m, 'probes': entries[m]} for m in sorted(entries)]
    print(json.dumps(result))


def cmd_get_library(args):
    if len(args) < 3:
        raise SystemExit('usage: get-library <manufacturer> <probe_name> <out.json>')
    manufacturer, probe_name, out_path = args[0], args[1], args[2]
    from probeinterface import get_probe
    probe = get_probe(manufacturer=manufacturer, probe_name=probe_name)
    d = pi_probe_to_ks4(
        probe,
        n_chan=_opt_int(args, '--n-chan'),
        wiring=_opt_wiring(args, '--wiring'),
        name=_opt(args, '--name') or probe_name,
        notes=_opt(args, '--notes'))
    _write_ks4(d, out_path)
    print(json.dumps({'out': out_path, 'n_contacts': len(d['chanMap'])}))


def cmd_generate(args):
    if len(args) < 2:
        raise SystemExit('usage: generate <spec.json> <out.json>')
    spec_path, out_path = args[0], args[1]
    with open(spec_path, 'r') as f:
        spec = json.load(f)
    probe = _build_generated(spec)
    d = pi_probe_to_ks4(
        probe,
        n_chan=spec.get('n_chan'),
        wiring=spec.get('wiring'),
        name=spec.get('name'),
        notes=spec.get('notes'))
    _write_ks4(d, out_path)
    print(json.dumps({'out': out_path, 'n_contacts': len(d['chanMap'])}))


def _build_generated(spec):
    from probeinterface import (
        generate_linear_probe, generate_multi_columns_probe, generate_tetrode)
    kind = str(spec.get('type', 'linear')).lower()
    p = spec.get('params', {}) or {}
    if kind in ('linear', 'linear_probe'):
        return generate_linear_probe(
            num_elec=int(p.get('num_elec', 16)),
            ypitch=float(p.get('ypitch', 20)))
    if kind in ('multi_columns', 'multi_column', 'multicolumns'):
        return generate_multi_columns_probe(
            num_columns=int(p.get('num_columns', 2)),
            num_contact_per_column=p.get('num_contact_per_column', 8),
            xpitch=float(p.get('xpitch', 20)),
            ypitch=float(p.get('ypitch', 20)),
            y_shift_per_column=p.get('y_shift_per_column'),
            contact_shapes=p.get('contact_shapes', 'circle'))
    if kind in ('tetrode', 'tetrodes'):
        return generate_tetrode(r=float(p.get('r', 10)))
    raise ValueError('unknown probe type: %s' % kind)


def cmd_describe(args):
    if len(args) < 1:
        raise SystemExit('usage: describe <in.json>')
    with open(args[0], 'r') as f:
        d = json.load(f)
    # Accept either a KS4 dict or a probeinterface JSON file.
    if 'xc' in d and 'yc' in d:
        summary = {
            'positions': [[a, b] for a, b in zip(d['xc'], d['yc'])],
            'shank_ids': [str(k) for k in d.get('kcoords', [])],
            'device_channel_indices': list(d.get('chanMap', [])),
            'n_chan': d.get('n_chan'),
            'notes': d.get('notes', ''),
        }
    else:
        from probeinterface import read_probeinterface
        pg = read_probeinterface(args[0])
        pr = pg.probes[0]
        np = _np()
        pos = np.asarray(pr.contact_positions, dtype=float)
        dci = getattr(pr, 'device_channel_indices', None)
        summary = {
            'positions': [[float(x), float(y)] for x, y in pos[:, :2]],
            'shank_ids': [str(s) for s in (pr.shank_ids
                          if pr.shank_ids is not None else [])],
            'device_channel_indices': ([int(v) for v in dci]
                                       if dci is not None else None),
            'n_chan': int(pos.shape[0]),
            'notes': _annotation_notes(pr),
        }
    print(json.dumps(summary))


# --------------------------------------------------------------------------
# tiny arg helpers (no argparse: keep behaviour identical across py versions)
# --------------------------------------------------------------------------
def _opt(args, flag):
    if flag in args:
        i = args.index(flag)
        if i + 1 < len(args):
            return args[i + 1]
    return None


def _opt_int(args, flag):
    v = _opt(args, flag)
    return int(v) if v is not None else None


def _opt_wiring(args, flag):
    v = _opt(args, flag)
    if not v:
        return None
    return [int(x) for x in v.replace(';', ',').split(',') if x.strip() != '']


COMMANDS = {
    'list-library': cmd_list_library,
    'get-library': cmd_get_library,
    'generate': cmd_generate,
    'describe': cmd_describe,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        raise SystemExit('usage: probe_tool.py {%s} ...' % '|'.join(COMMANDS))
    try:
        COMMANDS[sys.argv[1]](sys.argv[2:])
    except SystemExit:
        raise
    except Exception as e:
        sys.stderr.write('PROBE_TOOL_ERROR: %s\n%s\n' % (e, traceback.format_exc()))
        print('PROBE_TOOL_ERROR: %s' % e)
        sys.exit(1)


if __name__ == '__main__':
    main()
