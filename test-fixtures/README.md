# PnP-o-matic test fixtures

**97 ready-made fixtures** for the offline macOS print-and-play card imposition utility [PnP-o-matic](https://github.com/udeudeude/PnP-o-matic), with four independent 9-up duplex reference PDFs, one JSON manifest of checksums and expected behavior, and self-contained generators/validators. No AI-generated images, proprietary game art, or third-party runtime dependencies are used in the fixtures.

**Important distinction:** these are inputs and reference outputs, *not evidence the app itself passed its tests*. Physical print registration requires a duplex-capable printer and 100%-scale output. The intentionally broken files in `10-invalid-inputs/` should cause controlled errors, not successful imports.

## Quickest tests

1. **Long-edge duplex registration:** Import `01-registration/registration-fronts-9.pdf` using **Add Fronts**, import `registration-backs-9.pdf` using **Add Backs**; set **Poker**, **Letter**, **long-edge**, **no bleed**, **edge marks**. Export. Compare the *card positions and orientation* to `reference-outputs/letter-long-edge-expected-9up.pdf` (small cut-mark differences are not failures). Print both pages at **Actual Size / 100%**, duplex long-edge. Never use "fit to page".
2. **Short-edge registration:** Same inputs, switch to short-edge and compare to `reference-outputs/letter-short-edge-expected-9up.pdf`. Print short-edge only with matching printer setting. Repeat with A4 references if available.
3. **PDF page bounds:** Import `05-pdf-variations/all-distinct-page-boxes.pdf` and `nonzero-mediabox-origin.pdf`; change Automatic, TrimBox, CropBox, BleedBox, and MediaBox. Each option should crop to its own coordinates and never silently shift the content.
4. **Bleed:** Import `06-bleed-and-crop/3mm-bleed-with-distinct-boxes.pdf`. With 3 mm bleed on, the rust-colored border should extend beyond the blue trim outline without stealing pixels from neighboring cards.
5. **Deck importer modes:** `07-deck-import-patterns/separate-fronts-12.pdf` plus `separate-backs-12.pdf`, versus `alternating-front-back-24pages.pdf`, versus `first-half-fronts-second-half-backs-24pages.pdf`. All three should produce the same 12 correctly paired cards. Try `one-back-repeat-for-every-card.pdf` with Repeat One Back.
6. **Boundary lengths:** Import paired decks from `08-deck-lengths/`. Expected duplex output is **2 * ceil(card_count / 9)** PDF pages, with the final incomplete sheet retaining empty slots. Test 1, 8, 9, 10, 17, 18, 54, 55.
7. **Drag and pairing:** Import `09-pairing-and-order/fronts-10.pdf` and `backs-correct-10.pdf`; move fronts with pair lock on/off and Undo/Redo. `backs-reversed-10.pdf` is intentionally out of sequence: it should *not* be auto-assumed correct by a visual-only check. `backs-only-eight.pdf` leaves two backs missing.
8. **Unusual content and errors:** Drop images and mixed/rotated PDFs into individual preview slots. Try the broken files last; the app should remain responsive, explain rejected content, and preserve the existing deck.

## Duplex position oracle

The physical **card artwork is never mirrored**. Only the back *slots* are mirrored during sheet imposition. For page 1 fronts in top-to-bottom, left-to-right order, the expected back page identifiers are:

| Mode | Row 1 | Row 2 | Row 3 |
|---|---|---|---|
| Fronts | `1 2 3` | `4 5 6` | `7 8 9` |
| Long-edge backs | `3 2 1` | `6 5 4` | `9 8 7` |
| Short-edge backs | `7 8 9` | `4 5 6` | `1 2 3` |

The registration cards are deliberately asymmetric: red circle at the upper left, blue square at upper right, cross at lower left, green triangle at lower right. All have a visible TOP label. Looking only at centered numbers can conceal mirror/rotation bugs.

## Contents

| Folder | Focus |
|---|---|
| `01-registration/` | Nine paired PDF pages with distinct identities and orientation marks. |
| `02-card-sizes/` | Poker, Bridge, Euro, Tarot, 2.5-inch square, custom narrow/wide and landscape, plus mixed-size PDF. |
| `03-image-formats/` | PNG (RGBA/indexed/gray/1-bit/16-bit), JPEG (EXIF/ICC), TIFF/CMYK, BMP, GIF (including animated), WebP. |
| `04-resolution-color/` | 72/150/300/600 DPI metadata, various pixel counts, alpha, high-frequency detail, low-quality JPEG. |
| `05-pdf-variations/` | Vector, raster, mixed, transparency, embedded TTF font, `/Rotate` metadata, page box combinations and nonzero origins. |
| `06-bleed-and-crop/` | Exact 3 mm bleed vs poker trim, safe margins and hairlines, edge-to-edge artwork without bleed. |
| `07-deck-import-patterns/` | Separate, alternating, first-half/second-half, repeated back, odd-page imports, and an original procedural game deck, **Tidal Signal**. |
| `08-deck-lengths/` | Paired 1/8/9/10/17/18/54/55-page decks. |
| `09-pairing-and-order/` | Correct/reversed/short backs, 10-card front deck, individual slot-drop images and PDFs. |
| `10-invalid-inputs/` | Zero-byte, truncated, fake extension, empty valid PDF, password-protected PDF and SVG. |
| `reference-outputs/` | Four two-page Letter/A4 x long/short-edge 9-up oracles built independently of the app. |
| `generators/` | Fixture creator and integrity/geometry checker. |

`manifest.json` records every file's purpose, expected outcome, bytes, SHA-256, and relevant page/box/size metadata. Expectation values are `valid`, `invalid`, `encrypted`, `zero_pages`, `ambiguous`, and `unsupported`.

## Color and compatibility caveats

- **HEIC/HEIF is not included**: this Linux build environment lacks an HEVC image encoder, and substituting a JPEG renamed `.heic` would be a false test. On a supported Mac, you can add an authentic HEIC by converting `03-image-formats/baseline.jpg` in Preview (`File > Export`, choose HEIC if offered) or via `sips -s format heic 03-image-formats/baseline.jpg --out 03-image-formats/baseline.heic` where supported. Locally added files are not yet in `manifest.json`.
- WebP, animated GIF, and SVG acceptance varies with ImageIO/macOS and the application's deliberate supported-format policy. SVG is in **invalid inputs** to test a graceful unsupported-format response, not because SVG is inherently broken.
- An image's **pixel dimensions**, **DPI metadata**, and **physical printed dimensions** are different measurements. `04-resolution-color/fixed-750x1050-72dpi.jpg` through `600dpi.jpg` have identical pixels but different declared physical dimensions.
- The PDF with nonzero MediaBox origin is deliberately offset and partly clipped outside its specified page box; this catches coordinate-origin assumptions.
- The encrypted PDF's user password is **`testpass`**. It contains only a copy of registration card 1.
- The rendered reference sheets are not the app's own exports. A difference in cut-mark style is acceptable; card source IDs, side orientation, placement, and physical size are the primary assertions.
- Tarot 9-up cannot fit at 100% on Letter/A4. The app should show an explicit reduction, not falsely claim actual-size printing.

## Generation and verification

In a Python environment with `Pillow`, `reportlab`, `pypdf`, and `PyMuPDF`:

```bash
python3 -m pip install pillow reportlab pypdf pymupdf
python3 generators/generate.py
python3 generators/verify.py
```

The generator recreates fixtures and `manifest.json` using procedural drawings (no image generation service). It favors available Lato typefaces, otherwise standard PDF fonts; hashes may change across hosts because of font availability and library versions. The manifest is updated to match the locally generated files. `verify.py` checks hashes, metadata, PDF counts, box boundaries and the spatial duplex reference mappings; this does **not** exercise the actual macOS app or printer.

## Suggested regression acceptance criteria

- Imported card identity and front/back pairing are preserved through import, drag, lock/unlock, undo/redo and export.
- No PDF page is missing or duplicated. Duplex output has `2*ceil(n/9)` pages when n front/back pairs exist.
- Long-edge and short-edge use the mappings above, and source artwork itself is not reversed.
- The PDF page-box selector respects coordinates, nonzero origins and distinct trim/bleed extents.
- Bleed mode leaves independent gutters; margin-only cut marks do not cross card artwork.
- Image orientation, ICC profile/alpha and DPI handling do not fail silently; warn on ambiguous inputs or severe upscaling where appropriate.
- Invalid content never crashes or damages an already assembled deck.

**Usage warning:** if you copy the fixtures into your repo for automated tests, do not rely on `10-invalid-inputs/` all parsing successfully. Negative fixtures are intentional.
