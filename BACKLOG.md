# PnP-o-matic backlog

This is the **project backlog**, the working list of improvements, defects, validation, and ideas. Checkboxes describe implementation state, not a claim of real-printer verification. Priority is relative to the next public release.

## Implemented in v0.3.0 source (requires physical print validation)

- [x] Shared PDF-point sheet layout for preview and export, including the same trim-line segments.
- [x] Artwork bounds selector: Automatic / TrimBox / CropBox / BleedBox / MediaBox.
- [x] 3 mm bleed option with physically separated card gutters and trim marks.
- [x] Image dimensions based on embedded DPI with 300 DPI fallback.
- [x] Fit artwork vs Fill card with proportional scaling and crop.
- [x] Incomplete front/back pairing indicators and an export confirmation.
- [x] Linked front/back hover highlighting, insertion target highlight during drag.
- [x] Undo / Redo for card import, clear, replace, rearrange, and repeated backs.
- [x] Generated-PDF and deck-model regression tests (including short final sheets and duplex page counts).
- [x] Repeated common-back import and first-half-fronts / second-half-backs importer.
- [x] Tarot 2.75 x 4.75 inch and Square 2.5 x 2.5 inch presets.
- [x] Poker 2.5 x 3.5 inch, Bridge 2.25 x 3.5 inch and Euro 59 x 92 mm presets.
- [x] Side-by-side preview sheets and correct duplex long/short-edge back positions.
- [x] PDF and image drop per card, separate/alternating PDF import, pair-lock switch, drag rearranging.
- [x] Letter/A4 sheet output; margin-only or full-length cut lines; Preview output; user-level Mac installer.
- [x] Vertically scrollable editor so additional options remain reachable on smaller laptop windows.
- [x] Keep temporary export PDFs accessible after closing the editor; purge PDFs older than 24 hours on a subsequent launch.

## Verify before public release (highest priority)

- [ ] Use actual 9-front/9-back printable registration sheets to verify **long-edge and short-edge** duplex at 100% with physical folding/flipping on a real printer.
- [ ] Verify PDF TrimBox vs CropBox vs BleedBox with source files that have distinct page boxes, including clip and offset correctness.
- [ ] Verify 3 mm bleed and gutters do not crop neighboring artwork in actual printed sheets; examine PDF trim paths and print margins.
- [ ] Inspect the v0.3.0 UI at common 13-inch and 15-inch Mac window sizes; fix any clipped options or non-resizable preview.
- [ ] Verify 1, 8, 9, 10, 17, 54-card jobs, front-only, back-only and duplex output.
- [ ] Test drag across sheets, locked versus unlocked, Undo/Redo, interrupted imports and missing/unreadable files.
- [ ] Check image EXIF orientation and color management (JPEG, PNG, TIFF, HEIC) on real input files.
- [ ] Verify app and installer on macOS 11 and macOS 15, Intel and Apple Silicon where available.
- [ ] Publish an actual GitHub Release when physical and UI checks are satisfactory.

## Next practical UX work

- [ ] Whole-deck Cards view with drag reorder, bulk select and search (in addition to 9-up Sheets view).
- [ ] Better drag indicators distinguishing **insert**, **swap** and **replace**; expose a deliberate choice for occupied slots.
- [ ] Clear/Replace controls visible on card hover, plus keyboard Delete/Backspace.
- [ ] Show front/back pair identifiers in a status inspector rather than permanently covering artwork with source labels.
- [ ] Import chooser explaining Fronts, Backs, Alternating, First-Half/Second-Half and Repeat Back before importing.
- [ ] An error panel listing exact unreadable files, invalid pages, wrong-sized pages, and missing backs.
- [ ] Explicit odd-page alerts and user confirmation for ambiguous split imports.
- [ ] A way to choose **one repeated back vs repeat a sequence of backs**.
- [ ] Button to export fronts-only / backs-only PDFs as well as interleaved duplex output.
- [ ] Optional on-preview printable-area overlay based on printer margin settings.
- [ ] Dedicated visual duplex preview overlay (translucent front versus back) for confirming registration.

## Print-production features to consider

- [ ] Source page-box metadata inspector; choose Trim/Crop/Bleed boxes independently from final card trim dimensions.
- [ ] Editable bleed (0, 1/8 inch, 3 mm, custom) and independent inter-card gutter.
- [ ] Configurable cut-mark thickness, ink color, length and setback.
- [ ] Manual print registration calibration: X/Y offset for backs with printable calibration sheet.
- [ ] Rotation: individual card 90/180 degrees, orientation auto-detection and fit.
- [ ] Portrait/landscape page and optional 2x4 / 4x2 / adaptive max-fit imposition.
- [ ] Multiplicity/Copies per card and repeat entire selected groups.
- [ ] Save/open reusable \`.pnpomatic\` project files with relative source paths and missing-file relinking.
- [ ] Resolution warning for images that would print below user-selected DPI.
- [ ] Color-management and PDF transparency checks for production-quality printing.

## Engineering and reliability

- [ ] Break large main.swift into AppDelegate, MainWindowController, CardSlotView, SheetCanvasView and ImportController.
- [ ] Cache open PDFDocument and decoded image sources while imposing large decks; avoid reopening the same file per slot.
- [ ] More pixel-level PDF tests for visual mirroring and bleed/CropBox/TrimBox content, not only page counts and transforms.
- [ ] Document file import order and drag/drop edge cases with UI tests or controlled test harness.
- [ ] Detect and explain nonstandard PDF rotations and page-size changes mid-document.
- [ ] Detect when a stale temporary PDF is still open in Preview before pruning it; offer a Save As reminder.
- [ ] Consider explicit warning for unnotarized Mac builds; paid Apple Developer ID signing/notarization remains optional.
- [ ] Audit accessibility: VoiceOver labels, keyboard card navigation, contrast and scalable UI.
- [ ] Optimize startup, thumbnails and long-deck memory usage.
- [ ] Consider localization for inch/mm preferences and A4/Letter defaults.

## Not in scope for now

- A generic multi-purpose imposition/commercial prepress editor.
- A cloud service or required sign-in; this remains an offline macOS utility.
