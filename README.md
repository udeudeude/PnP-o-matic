# PnP-o-matic

A native macOS utility for turning PDFs with **one card per page** into print-ready **3×3 card sheets**.

## What it does

- Places pages 1–9 on sheet 1, pages 10–18 on sheet 2, and so on.
- Lets you add a second, third, or later PDF; every new PDF is appended after the cards already loaded.
- Supports **US Letter** and **A4**.
- Defaults to **Poker size: 2.5 × 3.5 in** finished cards.
- Includes **Bridge: 2.25 × 3.5 in** and **Euro: 59 × 92 mm** presets.
- Can instead use the source PDF page size or a custom width × height in inches or millimetres.
- The selected preset defines the finished cut rectangle; source artwork scales proportionally into it without distortion.
- Uniformly reduces the requested size only if a 3×3 grid cannot fit on the selected sheet.
- Opens the finished PDF in Preview.

### Cut-line modes

**Edge marks only**

Cut coordinates appear only in the margins outside the card grid. No guide line runs through card artwork.

**Full-page cut lines**

Thin horizontal and vertical cut lines extend across the complete sheet at every card boundary.

## Card sizes

The **Card size** menu offers:

- **Poker — 2.5 × 3.5 in** (default)
- **Bridge — 2.25 × 3.5 in**
- **Euro — 59 × 92 mm**
- **Use PDF page size**
- **Custom…** with inches or millimetres

The three built-in card presets fit 3×3 at full size on both US Letter and A4.

## Input order

Files are imposed in the order shown in the PnP-o-matic window. Additional drops append to the existing list rather than replacing it.

For example, 12 pages of heroes, 8 pages of items, and 5 pages of tokens become one 25-card sequence and three 9-up sheets.

## Compatibility

- macOS 11 Big Sur or later
- Intel Macs
- Apple Silicon Macs

The release build is universal.

## Development

    swift test
    MACOSX_DEPLOYMENT_TARGET=11.0 swift build -c release --product PnPOMaticApp

The app uses AppKit, PDFKit, Core Graphics, Foundation, and Uniform Type Identifiers with no third-party runtime dependencies.
