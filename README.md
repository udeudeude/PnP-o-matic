# PnP-o-matic

A native macOS print-and-play layout utility for building duplex-ready **3×3 card sheets** from PDFs and image files.

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
- **Use PDF page size**
- **Custom…** with inches or millimetres

The preset defines the finished cut rectangle. Source artwork is fitted proportionally without distortion.

The built-in Poker, Bridge, and Euro presets fit 3×3 at full size on both US Letter and A4.

## Cut-line modes

**Edge marks only**

Thin cut marks appear only in the margins beyond the cards. No guide line crosses the card artwork.

**Full-page cut lines**

Thin horizontal and vertical cut lines run across the complete sheet at every card boundary.

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
