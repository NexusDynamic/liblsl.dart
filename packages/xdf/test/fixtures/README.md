# Test fixtures

- `minimal.xdf`, `clock_resets.xdf`, `empty_streams.xdf`: the example files
  of [xdf-modules/example-files](https://github.com/xdf-modules/example-files)
  (MIT, see `LICENSE-example-files`).
- `pyxdf_reference.json`: what pyxdf 1.17.5 `load_xdf` makes of them, with
  its defaults and with `synchronize_clocks=False, dejitter_timestamps=False`
  (`raw`). Made with `tool/pyxdf_reference.py`.
