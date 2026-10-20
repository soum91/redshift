# Redshift

An iOS remote for a Tuya Wi-Fi IR blaster that skips Tuya's cloud. Every button press goes straight from the phone to the blaster over your Wi-Fi with Tuya's local protocol (3.3, 3.4 and 3.5), so it's instant and keeps working with the internet down.

## What's in it

- **Sony TV** remote that works right away. Codes are generated from Sony's SIRC protocol (power, input, volume, mute, channels, d-pad, home, back, options, guide, play, pause, Netflix, numbers). Any button can be re-learned from the real remote.
- **Sound bar** and **heater** remotes laid out for a Vizio sound bar and a De'Longhi heater. These are learned from the real remotes.
- **Custom** remotes for anything else: add buttons, name them, learn them.
- **Learn mode**: tap a button, aim the real remote at the blaster, press. The blaster captures the raw code locally.
- Hold-to-repeat on volume, bass, treble and temperature.
- Backup and restore of every remote and learned code as JSON.

## Setup

1. Sign in with Smart Life once (QR login, same as Exhale). This is only to fetch the blaster's local key. Or type the device ID and local key yourself.
2. Pick the blaster. Redshift scans your Wi-Fi for it, or you type its IP.
3. That's it. Smart Life isn't used again unless the blaster gets re-paired and its key changes.

## How it talks to the blaster

Two command formats exist, and Redshift detects which one yours uses:

- **Classic** (DP 201/202): `{"control":"send_ir","type":0,"head":"","key1":"1<base64>"}` on DP 201, learned codes arrive on DP 202.
- **Newer** (DP 1–13): DP 1 `study_key`, DP 7 the code, DP 13 `0`. Learned codes arrive on DP 2.

Codes are base64 of little-endian UInt16 microsecond durations, the same raw format tinytuya uses.

Protocol details from [tinytuya](https://github.com/jasonacox/tinytuya) (IRRemoteControlDevice) and the Home Assistant Tuya integration. Independent Swift implementation, not affiliated with Tuya.

## Build

GitHub Actions builds an unsigned IPA on every push to `main` and attaches it to a release. Sideload with AltStore, SideStore or Sideloadly.
