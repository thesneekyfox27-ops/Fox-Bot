# nrp-megaphone

Handheld megaphone, vehicle PA and stage microphones for The Neighborhood RP.
Based on [fd-megaphones](https://github.com/FD-Scripts/fd-megaphones) by pen / FD-Scripts (GPL-3.0, see LICENSE). Rewritten for qb-core + tgiann-inventory + pma-voice + ox_target / nrp-target.

## Install
1. **Remove / stop `fd-megaphones`** - don't run both.
2. Drop `nrp-megaphone` in resources, `ensure nrp-megaphone` after qb-core, ox_lib, pma-voice, tgiann-inventory, ox_target.
3. Your existing `megaphone` item must be **useable** (`useable = true`). Item name is `Config.ItemName`.

## How it works
| Mode | How | Range |
|---|---|---|
| Handheld | Use the `megaphone` item (again to lower it) | 60 m |
| Vehicle PA | **F12** in the front seat of an emergency vehicle / helicopter - PD, Sheriff, EMS only | 100 m |
| Stage mic | 3rd eye / [E] on a mic stand: "Use microphone" - stays on while you stand at it | 130 m |

A quiet click plays when you start talking and a static burst when you stop (config `Config.TalkSounds`; people nearby hear it faintly too).
Everyone near you hears the megaphone voice effect (also players who join while you're talking).
It switches off by itself when you drop / give away the item, go down, get cuffed, swim, leave the vehicle or step away from the mic, and on /relog.

## Hear yourself
While a megaphone / PA / mic is on, you hear your own voice played back through a megaphone
filter with a short echo (`Config.Monitor`). It uses your **Windows default microphone** and only
opens it while the megaphone is on. Use headphones - speakers can feed back.
`/megamonitor` turns it off / on for yourself (saved).
If FiveM blocks microphone access on a PC, the player gets one notice and everything else keeps working.

## Loudness
A normal voice fades out a few metres away, and the megaphone used to as well. Now everyone in range
hears it loud and steady, dropping only a little toward the edge of the range (`Config.Loudness`).
The vehicle PA is the loudest, then the stage mic, then the handheld (`Gain`). `FarVolume` is how loud
it still is at the very edge.

## Muffled through walls
If you're inside a building and the megaphone is outside (or there's a wall between you),
you still hear it clearly enough to understand, just a bit muffled and quieter, like it comes through the walls.
Same building / clear view = normal megaphone sound. Tune in `Config.Occlusion`
(`CutOff` = how muffled, `Volume` = how loud). Range stays capped by `Config.Range`.
