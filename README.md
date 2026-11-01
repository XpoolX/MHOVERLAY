# MHOverlay 1.0

**An in-game Monster Hunter Wilds overlay with monster HP, damage/DPS, consumable
buffs, live hunter stats, and customizable panels.**

[Download the latest release](https://github.com/XpoolX/MHOVERLAY/releases/latest)
| [Report an issue](https://github.com/XpoolX/MHOVERLAY/issues)

MHOverlay draws **inside the game** using REFramework's built-in Lua drawing
functions. It does not use a separate desktop window, so the overlay stays
visible when the game has focus in borderless fullscreen.

Developed for **macOS players running Wilds through Wine/NotProton**.
**REFramework is the only mod dependency: no Direct2D, reframework-d2d, CatLib,
.NET, or additional rendering plugins are required.** REFramework itself must
already work in your game/Wine setup.

**English and Spanish are included.** English is the default; select
**Language / Idioma > English / Espanol** in the REFramework menu. The choice is
saved with your settings and applies immediately to the menu and overlay.
Game-provided monster, hunter, and NPC names keep the game's language.

MHOverlay is an independent project inspired by HunterPie's functionality, not
an official HunterPie port. It displays information without changing your
character's attack, defense, buffs, or damage.

## Installation

1. Install a **REFramework build compatible with your version of Monster Hunter
   Wilds**. Confirm that its menu opens before installing MHOverlay.
2. Close the game.
3. Extract `MHOverlay-1.0.zip` and copy the included `reframework` folder into the
   game installation directory, alongside `MonsterHunterWilds.exe`.
4. Confirm the following files are present:

   ```text
   MonsterHunterWilds/
     MonsterHunterWilds.exe
     dinput8.dll                  <- REFramework; not included
     reframework/
       autorun/
         mhoverlay.lua
         mhoverlay/
           artwork.lua
           config.lua
           damage.lua
           icons.lua
           layouts.lua
           locale.lua
           model.lua
           portraits.lua
           view.lua
           wilds.lua
   ```

5. Launch the game and open **REFramework > Script Generated UI >
   MHOverlay 1.0 - Wilds**.
6. Choose your language, enable the panels you want, and adjust their positions,
   widths, scales, and background opacity. Select **Save settings**.
7. Optionally use **Preview and help > DEMO preview** to arrange the HUD.
   Demo values are fictional, clearly marked, and never saved as live data.
   Turn the demo off before playing.

**Updating:** with the game closed, replace `mhoverlay.lua` and the complete
`mhoverlay` module folder. **Keep `reframework/data`** to preserve your settings
and layouts. Older settings are migrated without resetting panel positions.

**Uninstalling:** remove `reframework/autorun/mhoverlay.lua` and
`reframework/autorun/mhoverlay/`. Optionally remove only `mhoverlay.json` and
`mhoverlay_layouts.json` from `reframework/data`. Do not delete REFramework or
other mods' files.

## Main features

| Panel | Information |
|---|---|
| Monsters | Current/max HP, health percentage, portraits, multiple-monster cards, pinned/quest-target prioritization |
| Focused monster | Expanded combat display for the monster you attack; small cards while exploring |
| Monster states | Rage, stamina/exhaustion, paralysis/stun tracking, completed part breaks, SDK wound-state counters |
| Damage / DPS | Identified hunter/support-hunter damage, DPS, contribution percentages, and group faint counter |
| Consumable buffs | Icons and available game timers for supported drugs, seeds, pills, powders, ammunition buffs, drinks, and other consumables |
| Hunter stats | Slim horizontal icon strip: attack, defense, affinity, weapon element/status power, and five elemental resistances |
| Village activities | Pending material collections, occupied slots, supply-ship cycle information, and available normal rations outside quests |
| Quest preview | Available players, hunter ranks, targets, faint limit, and time limit for the highlighted quest listing |

- Independent visibility, position, width, and scale for each panel.
- Global scale, background opacity, compact layouts, and sampling frequency.
- Automatically saved/restored layouts per game resolution.
- Hiding during supported loading screens, maps, full-screen menus, and NPC
  interactions. The quest-list preview is shown when appropriate.
- The last-hunt damage summary remains for two minutes after returning to the
  village; new activity resets it.
- Icon legends, opt-in demo preview, and collapsible advanced diagnostics.

### Reading the stat strip

Left to right: **attack, defense, affinity, weapon attribute, fire resistance,
water resistance, thunder resistance, ice resistance, dragon resistance**.

Sword = attack; shield = defense; target = affinity. The fourth icon changes to
match the weapon's element or status. A crossed circle means no element; `?`
means the attribute could not be read. An amber line indicates a partial reading.
The full legend is in **Preview and help > Icon legend**.

**Attack and element/status power use internal values**, without the display
multipliers used by the game's status screen. They are not damage-per-hit
predictions: hitzones, motion values, sharpness, and bonuses calculated only on
impact are not predicted or added manually. The panel reflects buffs already
applied to the current hunter values, not a theoretical maximum attack.

## Settings and troubleshooting

- **Save settings** writes `reframework/data/mhoverlay.json`.
- **Layouts per resolution** uses `reframework/data/mhoverlay_layouts.json`.
- Coordinates use the game's framebuffer pixels, not macOS desktop coordinates.
- **Advanced diagnostics > Update every N frames** controls the shared sampling
  interval; the default is 6 frames.
- `--` means unavailable, not zero. Check **Advanced diagnostics** and use
  **Clear warnings and retry** if a reader fails. Technical details retain the
  original error text so SDK method names and exception information are not lost.
- If another overlay or a Direct2D plugin fails in Wine, temporarily move the
  affected plugin and its dependent scripts out of REFramework's loading
  folders. MHOverlay does not require them.
- Text scaling requires a REFramework build with font-size support. Older builds
  keep their fixed text size; panels that cannot fit safely may not be drawn.
- If loading fails, check `re2_framework_log.txt` in the game directory.

### Compatibility and limitations

Core overlay behavior has been confirmed under macOS with Wine/NotProton, but
not every feature or SDK field has been verified in-game. Version 1.0 is a
packaged release, not a guarantee of compatibility with every game update,
REFramework build, or Wine configuration.

The DPS meter does not recover hits from before it started. Remote hits and
support-hunter identification depend on available game data. Palico and
environmental damage are not included. Individual DPS uses observed combat time.

Wound labels such as `NORMAL`, `TEAR`, and `RAW` are internal SDK states, not
guaranteed gameplay categories or counts of hits remaining. Completed part
breaks do not identify anatomy or confirm a severed tail.

The buff panel tracks supported consumables, not every melody, meal, skill, or
negative status. Ship cycle counters are not estimated arrival times.

## Support the project

If you enjoy MHOverlay and would like to support development, optional donations
are welcome. Donations are not required to use the mod.

**Bitcoin (BTC)**

```text
bc1qejskjgnan3ylm879x98edtcer54l86ltnfnaar
```

**Ethereum (ETH)**

```text
0x1Dd67251AdEcA76dE3fEB1913753Ca83aE927001
```

Double-check the address and the intended network before sending.

## Credits and third-party notices

- **REFramework**, by praydog and contributors, for in-game Lua scripting and
  drawing.
- **HunterPie**, for functional inspiration. No HunterPie source code, artwork,
  icons, or branding is included.
- **GreenComfyTea / YURI Overlay**, **JCubic / My Hunt Report**, and
  **TheCoCe / MHWildsCrownHelper**, for SDK reference implementations. Applicable
  MIT notices and source references are included in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).
- **CAPCOM**, for Monster Hunter Wilds. Monster portraits and six consumable
  drawings were converted from user-supplied game-art sheets; their rights
  remain with CAPCOM and/or their respective owners. Conversion does not confer
  ownership or assert redistribution permission. The flask and stat-strip
  drawings are original MHOverlay artwork.
- Everyone testing and reporting behavior under macOS, Wine, and NotProton.

## Development

No build step or external Lua dependencies are required:

```sh
lua tests/run.lua
luac -p reframework/autorun/mhoverlay.lua reframework/autorun/mhoverlay/*.lua tests/run.lua
git diff --check
```

Tests use SDK/drawing fixtures; they are not a substitute for in-game testing.

---

## Instalacion y uso en espanol

MHOverlay se dibuja dentro de Monster Hunter Wilds y solo necesita
**REFramework**. No requiere Direct2D, CatLib, .NET ni plugins graficos
adicionales. REFramework debe funcionar primero en tu instalacion de
Wine/NotProton.

Con el juego cerrado, extrae el ZIP y copia `reframework` junto a
`MonsterHunterWilds.exe`. Entra en **Script Generated UI > MHOverlay 1.0 - Wilds**
y selecciona **Language / Idioma > Espanol**. Ajusta cada panel y pulsa
**Guardar ajustes**. Al actualizar, reemplaza el script y la carpeta de modulos,
pero conserva `reframework/data`.

El menu agrupa monstruos, combate, buffs, estadisticas, actividades y vista previa
de misiones. La ayuda y el diagnostico quedan plegados. El cambio de idioma es
inmediato y no modifica posiciones ni valores leidos; los nombres propios
proporcionados por el juego conservan su idioma.

Ataque y elemento se muestran en unidades internas, no como dano por golpe ni
maximo teorico. `--` significa dato no disponible; la linea ambar en estadisticas
indica lectura parcial. Consulta **Diagnostico avanzado** y
**Limpiar avisos y reintentar dibujo** si hay fallos.

La compatibilidad depende de Wilds, REFramework y Wine/NotProton. No todas las
funciones estan confirmadas dentro del juego. Las donaciones BTC/ETH de arriba
son totalmente opcionales.
