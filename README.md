# sysclonev4 (clean start)

Minimal, patch-first, make-driven workflow for Pi imaging and Layer 1 seed.

## Quick start
```bash
mkdir -p ~/projects/sysclonev4 && cd ~/projects/sysclonev4
git init
git apply --index ../sysclonev4-all-in-one-v0.1.patch
git commit -m "v0.0.1: init skeleton + Makefile + L1 seed"
git tag -a v0.0.1 -m "v0.0.1 initial"
```
