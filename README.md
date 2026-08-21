# GSNAKE voor de Sanyo MBC-555

Een nieuwe 8088-port van **GSNAKE**, het Snake-spel dat oorspronkelijk in 1996
voor DOS is geschreven. De bronversie draaide op een 386 in VGA mode 13h; dit
project bouwt geen DOS-programma, maar een bootbare floppy-image voor de native
videohardware van de Sanyo MBC-555.

De port is in een vroege fase. Het systeem boot, schakelt naar 640×200 en toont
het omgezette menu. De eigenlijke spelinvoer, slanglogica, score, geluid en
andere schermen moeten nog worden overgezet.

## Doel en uitgangspunt

De oorspronkelijke bron staat één map hoger:

- `../GSNAKE.ASM` — oorspronkelijke TASM/MASM-bron;
- `../GSNAKE-NASM.ASM` — eerder naar NASM-syntaxis omgezette DOS-versie;
- `../MENU.DB` — originele VGA-menuafbeelding.

De Sanyo-versie staat geheel los van de DOS-uitvoer. De code in dit project is
opgezet voor de echte beperkingen van de MBC-555 en gebruikt daarom geen BIOS-
of DOS-videodiensten.

| Onderdeel | Originele GSNAKE | Sanyo-port |
| --- | --- | --- |
| CPU | 80386-instructies mogelijk | 8088 / `cpu 8086` |
| Video | VGA mode 13h, 320×200 | Native Sanyo RGB, 640×200 |
| Kleur | 256 paletkleuren | 3 bitplanes: rood, groen, blauw (8 kleuren) |
| Programma | DOS `.COM` | bootbare 180 KiB floppy-image |
| Videogeheugen | lineaire VGA-buffer op A000h | drie afzonderlijke, niet-lineair geordende planes |

De overgang van 256 naar 8 kleuren is bewust niet geautomatiseerd. De PNGs in
`assets/original-vga/` zijn uit de oude game geëxporteerd. Dithering en
kleurreductie voor de Sanyo worden handmatig gemaakt en de resultaten gaan in
`assets/sanyo/`.

## Huidige status

De huidige `app.asm` doet het volgende:

1. start de 640×200-modus;
2. wist de rode en groene bitplanes en vult de blauwe plane als achtergrond;
3. toont bij het starten `assets/sanyo/menu-ok-336x116.pic`, gecentreerd op x=152, y=40;
4. start het spel met `P` of spatie en keert bij een botsing terug naar het menu;
5. leest WASD en de vier cursorpijlen op het Sanyo-cijferblok (8/4/5/6);
6. tekent een bewegende, groeiende witte slang, een transparante gele voedselstip en een dubbelbrede ROM-score.

`menu-ok-336x116.pic` heeft geen header en bestaat uit drie lineaire planes in
blauw–groen–rood-volgorde. Elke plane bevat `336 / 8 × 116 = 4.872` bytes.

## Sanyo-video en afbeeldingsimport

De MBC-555 heeft vaste RGB-planes:

```asm
RED   equ 0f000h
GREEN equ 0800h
BLUE  equ 0f400h
```

In 640×200 bestaat een plane uit 50 blokken van vier scanlines. Een blok is
320 bytes groot. De vier bytes van één horizontale bytekolom horen bij de vier
scanlines van dat blok:

```text
byte 0, 1, 2, 3   = dezelfde x-positie op y, y+1, y+2, y+3
byte 4, 5, 6, 7   = volgende bytekolom op die vier scanlines
```

Een gedeeltelijke afbeelding kan daardoor niet met één `rep movsw` worden
gekopieerd. `copy_plane` in `app.asm` zet vier opeenvolgende bronregels om
naar deze indeling en springt na elke afbeeldingrij naar de volgende
320-byte-Sanyo-videorij.

Een afbeelding waarvan de hoogte of start-y geen veelvoud van vier is, vraagt
om extra behandeling bij een blokgrens. Houd imports tijdens deze eerste fase
daarom op een vier-scanlinegrens uitgelijnd.

## Bouwen en starten

Vereisten:

- NASM
- MAME met de `mbc55x`-machine

Start de game interactief vanuit deze map:

```sh
sh build.sh
```

Dit bouwt `app.img` en opent die image in een MAME-venster. `build.sh` sluit
eerst eventueel al draaiende MAME-processen.

## Visuele regressiecontrole

Gebruik na iedere aanpassing aan graphics of videogeheugen:

```sh
./capture.sh
```

Dit bouwt de image, start MAME zichtbaar voor drie seconden en slaat via
MAMEs ingebouwde snapshotfunctie het eindframe op als:

```text
captures/gsnake.png
```

De screenshot is native 640×200 en niet gefilterd. Een andere zichtbare duur
kan als argument:

```sh
./capture.sh 5
```

Deze capture-workflow is de voorkeursmanier om beeldconversies te controleren;
alleen assembleren is voor grafische wijzigingen niet voldoende.

## Werkafspraken

- Maak na iedere afgeronde, werkende stap een kleine Git-commit met een
  beschrijvende boodschap. Meng geen ongerelateerde wijzigingen in zo een
  commit.
- Bouw wijzigingen aan graphics, bitplanes of video-RAM altijd met
  `./capture.sh` en controleer `captures/gsnake.png` voordat je commit.
- Raadpleeg bij het porten van spelgedrag eerst `../GSNAKE-NASM.ASM`; neem de
  logica over, maar herschrijf VGA- en 386-specifieke code voor de 8088 en de
  Sanyo-VRAM-layout.

## Bestanden

| Pad | Rol |
| --- | --- |
| `app.asm` | Huidige GSNAKE-port en video-importcode |
| `header.asm` | Bootsector, floppy-loader, Sanyo-constanten en CRTC-initialisatie |
| `footer.asm` | Sector- en floppy-padding |
| `build.sh` | Bouwt en start MAME interactief |
| `capture.sh` | Bouwt, draait MAME kort en schrijft een screenshot |
| `assets/original-vga/` | Ongewijzigde PNG-export van de oude VGA-assets |
| `assets/sanyo/` | Handmatig gereduceerde/dithered Sanyo-assets en `.pic`-data |

`layout-test.asm` en `scanline-test.asm` zijn kleine hardwarediagnoses voor de
Sanyo-VRAM-layout. Ze zijn nuttig als referentie, maar zijn geen onderdeel van
het spel zelf.

## Grenzen en volgende stappen

De port mag niet terugvallen op 386-instructies, VGA-registers of een
256-kleurenpalet. Houd nieuwe code compact: de 8088 is trager en de boot-image
past op een enkelzijdige 180 KiB-floppy.

Logische vervolgstappen zijn:

1. pauzestand en sprites porten;
2. timing en moeilijkheidsgraad verfijnen;
3. elke grafische stap controleren met `./capture.sh`.

Gegenereerde `*.img`, `*.lst` en `captures/`-bestanden horen normaal niet in
een commit.
