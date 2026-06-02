# PythonKit Vendor Note

Upmarket vendors PythonKit so the `UpmarketRuntimeHelper` target builds deterministically with direct `xcodebuild -target UpmarketRuntimeHelper` invocations.

- Upstream: `https://github.com/pvieito/PythonKit`
- Version: `0.5.1`
- Revision: `6fee7617cfa910fbac7035276e295ba967adbbb4`
- License: Apache-2.0, included in `LICENSE.txt`

Do not edit vendored files directly unless a release-blocking helper build issue requires it. Prefer updating this directory from upstream, recording the new version/revision here, and running the helper build plus runtime validation gates.
