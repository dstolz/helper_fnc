import sys
import os
import json
import traceback


def load_config(path):
    with open(path, 'r') as f:
        return json.load(f)


def log(msg):
    print(msg, flush=True)


def amplifier_stream_id(path):
    from spikeinterface.extractors import get_neo_streams
    names, ids = get_neo_streams('intan', path)
    for n, i in zip(names, ids):
        if 'amplifier' in str(n).lower():
            return i
    return ids[0]


def read_one(path):
    import spikeinterface.extractors as se
    return se.read_intan(path, stream_id=amplifier_stream_id(path))


def load_recording(cfg):
    import spikeinterface.full as si
    folder = cfg['folder']
    fmt = cfg.get('recording_format', 'traditional')
    if fmt in ('one-file-per-signal', 'one-file-per-channel'):
        return read_one(os.path.join(folder, 'info.rhd'))
    files = cfg.get('files') or []
    paths = [os.path.join(folder, f) for f in files]
    paths = [p for p in paths if os.path.isfile(p)]
    if not paths:
        raise FileNotFoundError('No .rhd files found in ' + folder)
    recs = [read_one(p) for p in paths]
    if len(recs) == 1:
        return recs[0]
    return si.concatenate_recordings(recs)


def build_probe(cfg, rec):
    import re
    import numpy as np
    from probeinterface import Probe
    d = load_config(cfg['probe'])
    xc = np.asarray(d['xc'], dtype=float).ravel()
    yc = np.asarray(d['yc'], dtype=float).ravel()
    n = xc.size
    chan_map = np.asarray(d.get('chanMap', np.arange(n))).astype(int).ravel()
    kc = d.get('kcoords')
    if kc is not None:
        kc = np.asarray(kc).astype(int).ravel()

    # Map each probe site's nominal channel number to its actual position in
    # THIS recording. Native ids can have gaps when a hardware channel was
    # disabled at acquisition (e.g. 'A-016' missing shifts every later
    # channel down by one slot), so a site is dropped rather than assumed to
    # line up with the raw chanMap value.
    pos_by_number = {}
    for pos, cid in enumerate(rec.channel_ids):
        m = re.search(r'([0-9]+)$', str(cid))
        if m:
            pos_by_number[int(m.group(1))] = pos

    keep = np.array([int(v) in pos_by_number for v in chan_map])
    missing = [str(v) for v, k in zip(chan_map, keep) if not k]
    if missing:
        log('Probe site(s) for channel number(s) %s are not present in this '
            'recording (disabled at acquisition?); dropping from the probe.'
            % ', '.join(missing))

    dev_idx = np.array([pos_by_number[int(v)] for v in chan_map[keep]])
    probe = Probe(ndim=2, si_units='um')
    probe.set_contacts(positions=np.column_stack([xc[keep], yc[keep]]),
        shapes='circle', shape_params={'radius': 6})
    probe.set_device_channel_indices(dev_idx)
    if kc is not None and kc.size == n:
        probe.set_shank_ids(kc[keep].astype(str))
    return probe


def to_frames(periods_s, fs, n_samples):
    frames = []
    for p in periods_s:
        a = max(0, min(int(round(float(p[0]) * fs)), n_samples))
        b = max(0, min(int(round(float(p[1]) * fs)), n_samples))
        if b > a:
            frames.append((a, b))
    return frames


def _patch_silence_periods_dtype():
    # SilencedPeriodsRecording stores 'periods' as a structured np.array,
    # but run_sorter round-trips the whole recording through JSON
    # (dump -> tolist() -> json -> load) in-process before handing it to
    # Kilosort4, which collapses the structured array to a plain list of
    # lists. The constructor then rejects it. Patch the constructor here
    # so a reloaded plain list is rebuilt into the structured dtype.
    import numpy as np
    from spikeinterface.core.base import base_period_dtype
    from spikeinterface.preprocessing.silence_periods import SilencedPeriodsRecording as Cls
    if getattr(Cls, '_period_dtype_patched', False):
        return
    orig_init = Cls.__init__
    def patched_init(self, recording, periods=None, list_periods=None, mode='zeros', noise_levels=None, seed=None, **kwargs):
        if periods is not None and not isinstance(periods, np.ndarray):
            periods = np.array([tuple(row) for row in periods], dtype=base_period_dtype)
        orig_init(self, recording, periods=periods, list_periods=list_periods, mode=mode, noise_levels=noise_levels, seed=seed, **kwargs)
    Cls.__init__ = patched_init
    Cls._period_dtype_patched = True


def build_pipeline(cfg):
    import numpy as np
    import spikeinterface.preprocessing as spre
    rec = load_recording(cfg)
    log('Loaded recording: %d channels, %d samples, fs=%g, dtype=%s'
        % (rec.get_num_channels(), rec.get_num_samples(), rec.get_sampling_frequency(), rec.get_dtype()))

    # Intan amplifier data is stored as unsigned (offset-binary uint16);
    # Kilosort4 refuses unsigned dtypes, so always convert to signed.
    if rec.get_dtype().kind == 'u':
        rec = spre.unsigned_to_signed(rec)
        log('converted unsigned dtype to signed (%s)' % rec.get_dtype())

    # KS4 tmin/tmax are not accepted by the SI wrapper; honour them here by
    # cropping the recording (pop so they are not later flagged as dropped).
    ks = cfg.get('ks4', {}) or {}
    fs = rec.get_sampling_frequency()
    tmin = float(ks.pop('tmin', 0) or 0)
    tmax = ks.pop('tmax', None)
    if tmin > 0 or tmax is not None:
        end = int(round(float(tmax) * fs)) if (tmax is not None and np.isfinite(float(tmax))) else None
        rec = rec.frame_slice(start_frame=int(round(tmin * fs)), end_frame=end)
        log('cropped to tmin=%g tmax=%s (%d samples)' % (tmin, tmax, rec.get_num_samples()))

    orig_ids = list(rec.channel_ids)
    excl = cfg.get('exclude_channels', []) or []
    manual_bad = [orig_ids[i] for i in [int(x) for x in excl] if 0 <= i < len(orig_ids)]

    rec = rec.set_probe(build_probe(cfg, rec))
    pp = cfg.get('preprocessing', {})

    filt = pp.get('filter', {})
    if filt.get('enabled'):
        rec = spre.bandpass_filter(rec, freq_min=float(filt.get('freq_min', 300)),
                                   freq_max=float(filt.get('freq_max', 6000)))
        log('bandpass_filter %g-%g Hz' % (filt.get('freq_min', 300), filt.get('freq_max', 6000)))

    dbc = pp.get('detect_bad_channels', {})
    bad = list(manual_bad)
    if dbc.get('enabled'):
        det_rec = rec if filt.get('enabled') else spre.highpass_filter(rec, freq_min=300.0)
        auto_bad, labels = spre.detect_bad_channels(det_rec, method=dbc.get('method', 'coherence+psd'))
        log('detect_bad_channels flagged %d channel(s): %s'
            % (len(auto_bad), list(map(str, auto_bad))))
        for b in auto_bad:
            if b not in bad:
                bad.append(b)
    bad = [b for b in bad if b in list(rec.channel_ids)]
    if bad and len(bad) >= rec.get_num_channels():
        log('WARNING: bad-channel detection flagged all %d channel(s); skipping removal'
            % rec.get_num_channels())
        bad = []
    if bad:
        if dbc.get('action', 'remove') == 'interpolate':
            rec = spre.interpolate_bad_channels(rec, bad)
            log('interpolated %d bad channel(s)' % len(bad))
        else:
            rec = rec.remove_channels(bad)
            log('removed %d bad channel(s); %d remain' % (len(bad), rec.get_num_channels()))

    cmr = pp.get('common_reference', {})
    if cmr.get('enabled'):
        rec = spre.common_reference(rec, operator=cmr.get('operator', 'median'), reference='global')
        log('common_reference (%s)' % cmr.get('operator', 'median'))

    sil = pp.get('silence_periods', {})
    if sil.get('enabled'):
        periods = [[float(a) - tmin, float(b) - tmin] for (a, b) in (sil.get('periods_s', []) or [])]
        frames = to_frames(periods, fs, rec.get_num_samples())
        if frames:
            _patch_silence_periods_dtype()
            try:
                periods = np.array([(0, a, b) for (a, b) in frames],
                                   dtype=[('segment_index', 'int64'),
                                          ('start_sample_index', 'int64'),
                                          ('end_sample_index', 'int64')])
                rec = spre.silence_periods(rec, periods)
            except (ValueError, TypeError):
                rec = spre.silence_periods(rec, [frames])   # older list-per-segment API
            log('silenced %d artifact period(s)' % len(frames))

    return rec, bad


def ks4_params(cfg):
    import spikeinterface.sorters as ss
    requested = dict(cfg.get('ks4', {}) or {})
    try:
        accepted = ss.get_default_sorter_params('kilosort4')
    except Exception:
        accepted = {}
    params, dropped = {}, []
    for k, v in requested.items():
        if (not accepted) or (k in accepted):
            params[k] = v
        else:
            dropped.append(k)
    if dropped:
        log('Dropped %d KS4 setting(s) not accepted by the SI wrapper: %s' % (len(dropped), dropped))
    return params, dropped


def main():
    if len(sys.argv) < 2:
        raise SystemExit('usage: run_si_ks4.py <si_config.json> [--check]')
    cfg = load_config(sys.argv[1])
    check = '--check' in sys.argv[1:]
    status_path = cfg['status_path']
    if check:
        rec, bad = build_pipeline(cfg)
        params, dropped = ks4_params(cfg)
        log('CHECK OK: %d channel(s) feed Kilosort4 (probe %s); KS4 params %d ok, %d dropped'
            % (rec.get_num_channels(), os.path.basename(cfg['probe']), len(params), len(dropped)))
        return
    try:
        import spikeinterface.full as si
        rec, bad = build_pipeline(cfg)
        params, dropped = ks4_params(cfg)
        results_dir = cfg['results_dir']
        log('Running Kilosort4 via SpikeInterface -> %s' % results_dir)
        # Keep the preprocessed recording.dat that KS4 writes during sorting
        # (SI deletes it by default) so phy can display raw traces/waveforms.
        params.setdefault('delete_recording_dat', False)
        sorting = si.run_sorter('kilosort4', rec, folder=results_dir,
                                remove_existing_folder=True, verbose=True, **params)
        n_units = int(len(sorting.unit_ids))
        with open(status_path, 'w') as f:
            json.dump({'state': 'done', 'num_units': n_units,
                       'bad_channels': list(map(str, bad)), 'dropped_params': dropped}, f)
        log('KILOSORT4_DONE units=%d' % n_units)
    except Exception as e:
        with open(status_path, 'w') as f:
            json.dump({'state': 'error', 'message': str(e),
                       'traceback': traceback.format_exc()}, f)
        log('KILOSORT4_ERROR')
        raise


if __name__ == '__main__':
    main()
