# PnP-o-matic

A native macOS print-and-play layout utility for building duplex-ready **3×3 card sheets** from PDFs and image files.

## Current development build

**v0.3.0 (pre-release, pending real-printer validation)** adds Tarot and square presets, print-space/preview sharing, PDF box selection, bleed gutters, Fit/Fill, image DPI handling, mismatch warnings, linked hover highlights, Undo/Redo, a repeated common back, and first-half/second-half PDF importing.

See [BACKLOG.md](BACKLOG.md) for completed work, remaining features, print-test requirements, and known limitations.

## Workspace

PnP-o-matic shows **Fronts** and **Backs** side by side as miniature printed sheets. Each preview includes the page boundary, the nine card positions, empty slots, card numbers, and the selected trim-line style so the workspace closely matches the PDF it will generate.

- Front slots are numbered **1-2-3 / 4-5-6 / 7-8-9**.
- With normal portrait **long-edge duplex**, the back preview is physically mirrored as **3-2-1 / 6-5-4 / 9-8-7** so each printed back lands behind its corresponding front.
- A **short-edge duplex** option mirrors rows instead.
- Back artwork itself is not mirrored. Only its sheet position changes.

Use the sheet arrows to move through cards 10-18, 19-27, and so on.

## Adding cards

You can:

- Drop a PDF or image directly onto any numbered front or back slot.
- Drop a multi-page PDF onto a slot to fill that slot and the following slots.
- Use **Add Fronts…** to append a PDF containing all card fronts.
- Use **Add Backs…** to add a separate PDF containing all card backs. Pages pair with the corresponding front card number.
- Use **Import Alternating Front / Back PDF…** for PDFs ordered front, back, front, back.
- Add later PDFs or image files and continue the sequence.

Supported images are the image formats macOS can read through ImageIO.

## Rearranging cards

Drag an occupied slot to another numbered slot to rearrange it.

The **Lock corresponding fronts and backs while rearranging** switch is on by default:

- **On:** moving either side moves the whole front/back pair.
- **Off:** fronts and backs can be reordered independently.

Right-click a slot and choose **Clear This Slot** to remove its contents.

## Card sizes

The **Card size** menu offers:

- **Poker - 2.5 × 3.5 in** (default)
- **Bridge - 2.25 × 3.5 in**
- **Euro - 59 × 92 mm**
- **Tarot - 2.75 × 4.75 in** (9-up requires reduction on Letter/A4)
- **Square - 2.5 × 2.5 in**
- **Use PDF page size**
- **Custom…** with inches or millimetres

The preset defines the finished cut rectangle. Source artwork is fitted proportionally without distortion.

The built-in Poker, Bridge, and Euro presets fit 3×3 at full size on both US Letter and A4.

## Import formats and editing

- **Add Fronts…** and **Add Backs…**: separate sets of source pages paired by index.
- **Alternating**: front, back, front, back, ...
- **First Half / Second Half**: first N pages are fronts and next N are backs.
- **Repeat One Back…**: fill otherwise empty backs with one chosen page/image.
- Drop PDF pages or images into individual positions and rearrange cards with optional pair lock.
- **Undo** and **Redo** record changes to the deck; hovering over a slot highlights its corresponding side.
- Missing fronts/backs are flagged before duplex export, and users must confirm incomplete pairings.

## Artwork and bleed

- **Fit whole artwork** keeps the whole source visible; **Fill card** crops to the selected ratio.
- **PDF bounds** chooses Automatic, TrimBox, CropBox, BleedBox, or MediaBox. Automatic prefers a distinct TrimBox, otherwise CropBox.
- **Bleed** offers None or 3 mm. 3 mm allocates gutters, and may reduce the imposed size so nine cards fit. PDF source artwork outside TrimBox is available when the PDF contains a suitable BleedBox. The preview and PDF use the same trim coordinates.
- **Use PDF page size** with image inputs uses embedded DPI; images without DPI use a documented **300 DPI fallback**, not one PDF point per image pixel.
- Print at **Actual Size / 100%** and turn off the printer's automatic scaling to preserve intended physical dimensions.

## Cut-line modes

**Edge marks only**

Thin cut marks appear only in the margins beyond the cards. No guide line crosses the card artwork.

**Full-page cut lines**

Thin horizontal and vertical cut lines run across the complete sheet at every card boundary.

## Accuracy considerations

**Tarot-size cards cannot fit nine at 100% on US Letter or A4**. The UI displays the resulting scale when you choose a larger card size or enable 3 mm bleed.

Three-millimetre bleed cannot simply overlap neighboring cards; the spacing is included in the sheet geometry. Verify registration and any bleed details using a small physical test batch before printing a complete deck.

Output PDFs remain available for Preview after the editor closes. Temporary files older than 24 hours are removed when PnP-o-matic starts again.

## Output

When fronts and backs are present, output pages alternate:

1. Front sheet 1
2. Back sheet 1, mirrored for the selected duplex flip
3. Front sheet 2
4. Back sheet 2
5. and so on

The generated PDF opens in Preview.

## Compatibility

- macOS 11 Big Sur or later
- Intel Macs
- Apple Silicon Macs

CI builds a universal Intel + Apple Silicon app and verifies the macOS 11 deployment target.

## Development

    swift test
    MACOSX_DEPLOYMENT_TARGET=11.0 swift build -c release --product PnPOMaticApp

The app uses AppKit, PDFKit, Core Graphics, ImageIO, Foundation, and Uniform Type Identifiers with no third-party runtime dependencies.
