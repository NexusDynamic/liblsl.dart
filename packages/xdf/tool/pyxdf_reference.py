# Writes test/fixtures/pyxdf_reference.json (run from the package root in an
# environment with pyxdf: `uv run --with pyxdf python tool/pyxdf_reference.py`).
import json, sys, pyxdf, numpy as np
out = {}
for f in ['minimal', 'clock_resets', 'empty_streams']:
    res = {}
    for mode, kw in [('default', {}), ('raw', dict(synchronize_clocks=False, dejitter_timestamps=False))]:
        streams, header = pyxdf.load_xdf(f'test/fixtures/{f}.xdf', **kw)
        ss = []
        for s in streams:
            i = s['info']; ts = s['time_stamps']; x = s['time_series']
            d = dict(id=int(i['stream_id']), name=i['name'][0], n=int(len(ts)),
                     effective_srate=float(i['effective_srate']),
                     segments=[list(map(int, g)) for g in i['segments']],
                     clock_segments=[list(map(int, g)) for g in i['clock_segments']],
                     ts_head=[float(v) for v in ts[:5]], ts_tail=[float(v) for v in ts[-5:]],
                     ts_every=[float(v) for v in ts[::max(1, len(ts)//50)]])
            if i['channel_format'][0] == 'string':
                d['str_head'] = [list(r) for r in x[:3]]; d['str_tail'] = [list(r) for r in x[-3:]]
            elif len(ts):
                d['val_head'] = np.asarray(x[:3], dtype=float).tolist(); d['val_tail'] = np.asarray(x[-3:], dtype=float).tolist()
            ss.append(d)
        res[mode] = ss
    out[f] = res
json.dump(out, open('test/fixtures/pyxdf_reference.json', 'w'), indent=1)
print('ok')
