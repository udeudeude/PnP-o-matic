#!/usr/bin/env python3
"""Build an at-a-glance fixture contact sheet using existing PDFs and images."""
from pathlib import Path
import fitz
from PIL import Image, ImageOps, ImageDraw, ImageFont
import io
ROOT=Path(__file__).resolve().parents[1]
SAMPLES=[
 ('1. Registration front','01-registration/registration-fronts-9.pdf',0),
 ('2. Registration back','01-registration/registration-backs-9.pdf',0),
 ('3. Tarot card','02-card-sizes/tarot-source.pdf',0),
 ('4. Square card','02-card-sizes/square-2p5-source.pdf',0),
 ('5. Transparency','03-image-formats/rgba-transparent.png',0),
 ('6. JPEG artwork','03-image-formats/baseline.jpg',0),
 ('7. PDF page boxes','05-pdf-variations/all-distinct-page-boxes.pdf',0),
 ('8. 3 mm bleed','06-bleed-and-crop/3mm-bleed-with-distinct-boxes.pdf',0),
 ('9. Tidal Signal front','07-deck-import-patterns/tidal-signal-fronts-12.pdf',0),
 ('10. Tidal Signal back','07-deck-import-patterns/tidal-signal-backs-12.pdf',0),
 ('11. Letter front reference','reference-outputs/letter-long-edge-expected-9up.pdf',0),
 ('12. Letter back reference','reference-outputs/letter-long-edge-expected-9up.pdf',1)
]
W,H=1260,1160
out=Image.new('RGB',(W,H),'#EEECE5')
d=ImageDraw.Draw(out)
try:
 f=ImageFont.truetype('/usr/share/fonts/truetype/lato/Lato-Bold.ttf',17)
 title=ImageFont.truetype('/usr/share/fonts/truetype/lato/Lato-Bold.ttf',32)
except OSError:f=ImageFont.load_default();title=f
d.text((42,25),'PnP-o-matic  /  Test Fixture Catalog',fill='#183747',font=title)
d.text((43,70),'Representative inputs and independent duplex reference sheets',fill='#4C6170',font=f)
cellw,cellh=270,324
for i,(name,path,page) in enumerate(SAMPLES):
 col=i%4;row=i//4;x=42+col*303;y=115+row*344
 d.rounded_rectangle((x,y,x+cellw,y+cellh),radius=8,fill='white',outline='#D2D4D0',width=2)
 source=ROOT/path
 if source.suffix=='.pdf':
  with fitz.open(source) as pdf:
   p=pdf[page];pix=p.get_pixmap(matrix=fitz.Matrix(1.2,1.2),alpha=False)
   thumb=Image.open(io.BytesIO(pix.tobytes('png'))).convert('RGB')
 else:
  with Image.open(source) as original:
   thumb=original.convert('RGBA');bg=Image.new('RGBA',thumb.size,'#DDDDDD');bg.alpha_composite(thumb);thumb=bg.convert('RGB')
 thumb.thumbnail((cellw-18,cellh-55),Image.Resampling.LANCZOS)
 px=x+(cellw-thumb.width)//2;py=y+9+(cellh-57-thumb.height)//2
 out.paste(thumb,(px,py));d.text((x+12,y+cellh-35),name,font=f,fill='#243F50')
out.save(ROOT/'CATALOG.png')
print(ROOT/'CATALOG.png')
