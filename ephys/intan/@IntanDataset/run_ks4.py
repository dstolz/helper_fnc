import sys
import json
import os
import traceback
from kilosort import run_kilosort
from kilosort.io import load_probe


def main():
    if len(sys.argv) < 2:
        raise SystemExit('usage: run_ks4.py <settings.json>')
    with open(sys.argv[1], 'r') as f:
        cfg = json.load(f)

    status_path = os.path.join(cfg['results_dir'], 'ks4_status.json')

    probe = load_probe(cfg['probe'])
    settings = {
        'n_chan_bin': cfg['n_chan_bin'],
        'fs': cfg['fs'],
        'filename': cfg['filename'],
        'results_dir': cfg['results_dir'],
    }
    # carry any extra settings provided by MATLAB
    for k, v in cfg.items():
        if k not in ('probe', 'data_dtype'):
            settings[k] = v

    try:
        run_kilosort(
            settings=settings,
            probe=probe,
            filename=cfg['filename'],
            data_dtype=cfg['data_dtype'],
            results_dir=cfg['results_dir'],
        )
        with open(status_path, 'w') as f:
            json.dump({'state': 'done'}, f)
        print('KILOSORT4_DONE')
    except Exception as e:
        with open(status_path, 'w') as f:
            json.dump({'state': 'error', 'message': str(e),
                       'traceback': traceback.format_exc()}, f)
        print('KILOSORT4_ERROR')
        raise


if __name__ == '__main__':
    main()
