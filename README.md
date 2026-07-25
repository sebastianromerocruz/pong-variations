# Pong Variations

A Game Boy implementation of Pong, written in Game Boy assembly (SM83) using [RGBDS](https://rgbds.gbdev.io/).

## Status

Early in development. Currently:

- Renders a paddle (3 stacked tiles) and a ball tile on screen via the tilemap and OAM.
- Reads Control Pad input (Up/Down) during VBlank, though paddle movement is not yet wired up.
- No scoring, AI, or second paddle yet—this is a foundation to build the actual gameplay on top of.

## Requirements

- [RGBDS](https://rgbds.gbdev.io/) 0.5.0 or later (provides `rgbasm`, `rgblink`, `rgbfix`)
- A Game Boy emulator capable of opening `.gb` ROMs (the `make run` target uses macOS `open`, so it will launch whatever emulator is registered to handle that file type)

## Building

```sh
make        # assemble, link, and fix the ROM -> pong.gb
make run    # open pong.gb in the default Game Boy emulator
make clean  # remove build artifacts (pong.gb, pong.o, pong.sym)
```

## Project structure

- [pong.asm](pong.asm): main source: header, initialization, game loop, interrupt handler, tile/tilemap data
- [hardware.inc](hardware.inc): standard [gbdev hardware.inc](https://github.com/gbdev/hardware.inc) constants for Game Boy hardware registers
- [makefile](makefile): build, run, and clean targets
