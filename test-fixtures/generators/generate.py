#!/usr/bin/env python3
"""Deterministically build the PnP-o-matic test fixture library; no AI imagery.
Dependencies: reportlab, pillow, pypdf, PyMuPDF (fitz), optional pillow-heif.
Run from anywhere: python generators/generate.py
"""
from __future__ import annotations
import io, os, math, json, random, hashlib, shutil
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, Color, white, black
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.utils import ImageReader
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageCms
from pypdf import PdfReader, PdfWriter
from pypdf.generic import RectangleObject, NameObject, NumberObject
import fitz

ROOT=Path(__file__).resolve().parents[1]
RANDOM=random.Random(20261007)
PT=72
MM=72/25.4
POKER=(180.,252.)
COLORS=['#193E50','#BC6545','#718E74','#D1A64E','#76586D','#446C85','#A77B44','#587B6B','#7E4A4B']
SECTIONS={
 'registration':'01-registration', 'sizes':'02-card-sizes', 'formats':'03-image-formats',
 'quality':'04-resolution-color', 'pdfs':'05-pdf-variations', 'bleed':'06-bleed-and-crop',
 'imports':'07-deck-import-patterns', 'lengths':'08-deck-lengths', 'pairing':'09-pairing-and-order',
 'invalid':'10-invalid-inputs', 'reference':'reference-outputs'
}
records=[]
for d in SECTIONS.values(): (ROOT/d).mkdir(parents=True,exist_ok=True)
FONT_DIR=Path('/usr/share/fonts/truetype/lato')
regular=FONT_DIR/'Lato-Regular.ttf'; bold=FONT_DIR/'Lato-Bold.ttf'
if regular.exists():
 pdfmetrics.registerFont(TTFont('FixtureSans',str(regular)))
 pdfmetrics.registerFont(TTFont('FixtureBold',str(bold)))
 FN,FB='FixtureSans','FixtureBold'
else: FN,FB='Helvetica','Helvetica-Bold'

def rel(p):return p.relative_to(ROOT).as_posix()
def track(p, description, *, expected='valid', pages=None, details=None):
 entry={'path':rel(p),'purpose':description,'expected':expected}
 if pages is not None:entry['pdf_pages']=pages
 if details:entry['details']=details
 records.append(entry)
def new_pdf(dest,pages,draw):
 c=canvas.Canvas(str(dest),pagesize=POKER,pageCompression=1, invariant=1)
 c.setTitle(dest.stem)
 for n,item in enumerate(pages):
  size=item.get('size',POKER) if isinstance(item,dict) else POKER
  c.setPageSize(size)
  draw(c,n,item,size)
  c.showPage()
 c.save()
 return dest

def poly(c,pts,fill=0,stroke=1):
 p=c.beginPath();p.moveTo(*pts[0]);[p.lineTo(*xy) for xy in pts[1:]];p.close()
 c.drawPath(p,fill=fill,stroke=stroke)

def round_rect(c,x,y,w,h,r,fill,stroke=None):
 c.setFillColor(HexColor(fill));c.setStrokeColor(HexColor(stroke or fill))
 c.roundRect(x,y,w,h,r,fill=1,stroke=int(stroke is not None))

def card(c,n,side,size=POKER,theme='register'):
 w,h=size;code=n+1
 c.saveState();c.setFillColor(HexColor('#F9F6EE'));c.rect(0,0,w,h,fill=1,stroke=0)
 if theme=='register':
  color=HexColor(COLORS[n%len(COLORS)])
  c.setLineWidth(1.25);c.setStrokeColor(color);c.rect(9,9,w-18,h-18)
  c.setLineWidth(.4);c.setStrokeColor(HexColor('#777777'))
  for x in range(20,int(w)-12,12):c.line(x,0,x,6);c.line(x,h-6,x,h)
  for y in range(20,int(h)-12,12):c.line(0,y,6,y);c.line(w-6,y,w,y)
  round_rect(c,18,h-46,w-36,30,5,COLORS[n%len(COLORS)])
  c.setFillColor(white);c.setFont(FB,13);c.drawCentredString(w/2,h-35,'FRONT' if side=='F' else 'BACK')
  c.setFillColor(color);c.setFont(FB,min(65,w*.35));c.drawCentredString(w/2,h*.47,f'{code:02d}')
  c.setFont(FN,9);c.drawCentredString(w/2,h*.31,f'PAIR  {code:02d}  /  09')
  c.setFont(FB,10);c.drawCentredString(w/2,26,'TOP  ^')
  # Deliberate asymmetry, unique symbols at EACH corner.
  c.setFillColor(HexColor('#C24435'));c.circle(15,h-15,5,fill=1,stroke=0)
  c.setFillColor(HexColor('#164E84'));c.rect(w-21,h-21,12,12,fill=1,stroke=0)
  c.setStrokeColor(HexColor('#B58C38'));c.setLineWidth(3)
  c.line(12,18,24,18);c.line(18,12,18,24)
  c.setFillColor(HexColor('#38785F'));poly(c,[(w-27,11),(w-11,11),(w-19,28)],fill=1,stroke=0)
  c.setFillColor(HexColor('#333333'));c.setFont(FN,7)
  c.drawCentredString(w/2,12,'RED DOT = UPPER LEFT')
 else:
  # An invented game deck with programmable vector artwork, not image-gen.
  color=HexColor(COLORS[n%len(COLORS)])
  c.setFillColor(HexColor('#162C3C'));c.rect(0,0,w,h,fill=1,stroke=0)
  c.setFillColor(HexColor('#F5ECD5'));c.roundRect(8,8,w-16,h-16,6,fill=1,stroke=0)
  c.setStrokeColor(color);c.setLineWidth(1.8);c.roundRect(12,12,w-24,h-24,4)
  if side=='B':
   c.setFillColor(color);c.roundRect(18,18,w-36,h-36,5,fill=1,stroke=0)
   c.setStrokeColor(HexColor('#F0DBAA'));c.setLineWidth(1)
   for i in range(12):
    y=h/2+(i-5.5)*11
    c.line(28,y,w-28,y)
   for i in range(6):
    c.circle(w/2,h/2,8+i*11,fill=0,stroke=1)
   c.setFillColor(HexColor('#F5ECD5'));c.circle(w/2,h/2,18,fill=1,stroke=0)
   c.setFillColor(color);c.setFont(FB,16);c.drawCentredString(w/2,h/2-6,'TS')
   c.setFillColor(HexColor('#F8E9C9'));c.setFont(FB,10);c.drawCentredString(w/2,34,'TIDAL SIGNAL')
  else:
   c.setFillColor(color);c.roundRect(19,h-47,w-38,26,4,fill=1,stroke=0)
   c.setFillColor(white);c.setFont(FB,11);c.drawCentredString(w/2,h-39,['THE SOUNDING','LANTERN BUOY','NORTH CURRENT','THE REEF','THE OBSERVER','LOW TIDE','BEACON','FOG SIGNAL','THE ARCHIVE','DRIFT MAP','HARBOR','DEEP WATER'][n%12])
   # decorative vector seascape.
   c.setFillColor(HexColor('#DFD9C8'));c.roundRect(21,85,w-42,h-145,3,fill=1,stroke=0)
   y0=h*.53
   c.setStrokeColor(color)
   for k in range(8):
    p=c.beginPath();p.moveTo(29,y0-37+k*9)
    for x in range(30,int(w)-26,3):
     y=y0-37+k*9+4*math.sin(x*.085+n*.5+k*.8)
     p.lineTo(x,y)
    c.setLineWidth(.7 if k%2 else 1.2);c.drawPath(p)
   c.setFillColor(HexColor('#D8A84D'));c.circle(w*.71,h*.65,14+(n%3)*3,fill=1,stroke=0)
   c.setFillColor(color);c.setFont(FB,9);c.drawCentredString(w/2,72,f'SIGNAL {n+1:02d} / 12')
   c.setFillColor(HexColor('#283C48'));c.setFont(FN,8)
   c.drawCentredString(w/2,53,'Follow the tide; keep the signal.')
   c.drawCentredString(w/2,42,'Gain 1 mark when the beacon returns.')
   c.setFont(FB,8);c.drawCentredString(w/2,24,f'CARD  {n+1:02d}  -  TIDAL SIGNAL')
 c.restoreState()

def deck(dest,n,side='F',theme='register',indices=None):
 ids=list(range(n)) if indices is None else indices
 new_pdf(dest,[{'size':POKER,'id':i} for i in ids],lambda c,j,p,s:card(c,p['id'],side,s,theme))
 return dest

def mixed_deck(dest,indices,sides,theme='register'):
 new_pdf(dest,[{'size':POKER,'id':i,'side':side} for i,side in zip(indices,sides)],lambda c,j,p,s:card(c,p['id'],p['side'],s,theme))
 return dest

def ref_sheet(c,side,duplex,format_name):
 # independent reference: no import from application; fit 9 standard Poker cards without scaling.
 page_w,page_h = ((612,792) if format_name=='letter' else (595.2756,841.8898))
 c.setPageSize((page_w,page_h))
 w,h=POKER;xo=(page_w-3*w)/2;yo=(page_h-3*h)/2
 c.setFillColor(white);c.rect(0,0,page_w,page_h,fill=1,stroke=0)
 for row in range(3):
  for col in range(3):
   slot=row*3+col
   source_col = 2-col if side=='B' and duplex=='long' else col
   source_row = 2-row if side=='B' and duplex=='short' else row
   card_id=source_row*3+source_col
   x=xo+col*w; y=page_h-yo-(row+1)*h
   c.saveState();c.translate(x,y);card(c,card_id,side,POKER);c.restoreState()
   c.setStrokeColor(HexColor('#242424'));c.setLineWidth(.35)
   # non-invasive margin marks; full grid not drawn over card artwork
   for dx in (0,w):
    for dy in (0,h):
     xx=x+dx;yy=y+dy
     d=-1 if dx==0 else 1
     c.line(xx+d*3,yy,xx+d*9,yy)
     d=-1 if dy==0 else 1
     c.line(xx,yy+d*3,xx,yy+d*9)

# 01 registration source files and reference output mappings
reg_front=ROOT/SECTIONS['registration']/'registration-fronts-9.pdf'
reg_back=ROOT/SECTIONS['registration']/'registration-backs-9.pdf'
track(deck(reg_front,9,'F'),'Nine unique portrait fronts, one card per PDF page',pages=9)
track(deck(reg_back,9,'B'),'Corresponding backs, one per page, never mirror the artwork',pages=9)
for fmt in ('letter','a4'):
 for flip in ('long','short'):
  p=ROOT/SECTIONS['reference']/f'{fmt}-{flip}-edge-expected-9up.pdf'
  c=canvas.Canvas(str(p),pagesize=(612,792),invariant=1,pageCompression=1)
  c.setTitle('Independent expected 9-up duplex layout')
  for side in ['F','B']:
   ref_sheet(c,side,flip,fmt);c.showPage()
  c.save()
  track(p,f'Independent {fmt.upper()} {flip}-edge duplex reference, 2 pages',pages=2,details={'expected_back_positions':([3,2,1,6,5,4,9,8,7] if flip=='long' else [7,8,9,4,5,6,1,2,3])})

# 02 cut dimensions, portrait, landscape, square, custom, mixed page sizes
SIZE_DEFS=[('poker',POKER),('bridge',(162.,252.)),('euro-59x92',(59*MM,92*MM)),('tarot',(198.,342.)),('square-2p5',(180.,180.)),('custom-narrow',(90.,260.)),('custom-wide',(280.,140.)),('landscape-poker',(252.,180.))]
for name,sz in SIZE_DEFS:
 p=ROOT/SECTIONS['sizes']/f'{name}-source.pdf'
 def dimension_card(c,j,a,s):
  card(c,j,'F',s)
  # Dimension annotation lives inside the top banner, not over the big card ID.
  round_rect(c,18,s[1]-46,s[0]-36,30,5,COLORS[j%len(COLORS)])
  c.setFillColor(white);c.setFont(FB,11 if s[0]>125 else 9)
  c.drawCentredString(s[0]/2,s[1]-29,'FRONT')
  label=f'{s[0]/72:.2f}x{s[1]/72:.2f} in'
  c.setFont(FN,7 if s[0]>125 else 6)
  c.drawCentredString(s[0]/2,s[1]-41,label)
 new_pdf(p,[{'size':sz}],dimension_card)
 track(p,f'Explicit {name} size, in PDF points {sz[0]:.2f} x {sz[1]:.2f}',pages=1,details={'size_points':list(sz)})
p=ROOT/SECTIONS['sizes']/'mixed-size-pages.pdf'
new_pdf(p,[{'size':sz} for _,sz in SIZE_DEFS],lambda c,j,a,s:card(c,j,'F',s))
track(p,'Eight pages with mixed size/orientation; should not silently assume uniform sizes',pages=len(SIZE_DEFS))

# bitmap drawing utilities
try:
 from PIL import ImageFont
 font=ImageFont.truetype(str(regular),25) if regular.exists() else ImageFont.load_default()
 bigfont=ImageFont.truetype(str(bold),58) if bold.exists() else ImageFont.load_default()
except OSError:font=ImageFont.load_default();bigfont=ImageFont.load_default()

def bitmap(n=1,sz=(750,1050),mode='RGB'):
 if sz[0]<400 or sz[1]<550:
  return bitmap(n,(750,1050),mode).resize(sz,Image.Resampling.LANCZOS)
 w,h=sz
 im=Image.new('RGB',sz,'#F8F1DF');d=ImageDraw.Draw(im)
 d.rounded_rectangle((25,25,w-25,h-25),radius=24,outline='#173D52',width=max(2,w//200))
 d.rectangle((55,70,w-55,170),fill=COLORS[n%len(COLORS)])
 d.text((w//2,110),'PnP-o-matic',font=font,fill='white',anchor='mm')
 d.text((w//2,h//2-20),f'{n:02d}',font=bigfont,fill='#173D52',anchor='mm')
 for j in range(10):
  x=60+j*(w-120)/9
  pts=[(x,h*.63+20*math.sin(k*.13+n+j)) for k in range(60)]
  d.line(pts,fill=COLORS[(j+n)%len(COLORS)],width=2)
 d.polygon([(75,240),(125,240),(100,180)],fill='#CC6C48')
 d.ellipse((w-125,180,w-75,230),fill='#4F8177')
 d.text((w//2,h-115),'TOP ^  /  BOTTOM v',font=font,fill='#173D52',anchor='mm')
 if mode=='RGBA':
  im=im.convert('RGBA')
  # transparent diagonal corner, useful for alpha/premultiplication tests.
  alpha=Image.new('L',sz,255);da=ImageDraw.Draw(alpha)
  da.polygon([(0,0),(w//3,0),(0,h//3)],fill=0)
  im.putalpha(alpha)
 return im

# 03 Image formats / EXIF / alpha, including formats not universally supported
pdir=ROOT/SECTIONS['formats']
base=bitmap()
imgs=[('rgb.png',lambda p:base.save(p,'PNG')),
      ('rgba-transparent.png',lambda p:bitmap(mode='RGBA').save(p,'PNG')),
      ('palette-indexed.png',lambda p:base.quantize(colors=32).save(p,'PNG')),
      ('baseline.jpg',lambda p:base.save(p,'JPEG',quality=90,subsampling=0)),
      ('grayscale.png',lambda p:base.convert('L').save(p,'PNG')),
      ('monochrome-1bit.png',lambda p:base.convert('1').save(p,'PNG')),
      ('rgb.tiff',lambda p:base.save(p,'TIFF',compression='tiff_lzw')),
      ('cmyk.tif',lambda p:base.convert('CMYK').save(p,'TIFF')),
      ('standard.bmp',lambda p:base.save(p,'BMP')),
      ('single-frame.gif',lambda p:base.quantize(colors=64).save(p,'GIF')),
      ('webp.webp',lambda p:base.save(p,'WEBP',quality=90))]
for name,fn in imgs:
 p=pdir/name
 try:
  fn(p);track(p,f'{name} raster decoder/alpha/color-mode input')
 except (OSError,ValueError) as ex: print('SKIP',name,str(ex))
frames=[bitmap(i,(360,504)).quantize(colors=64) for i in range(1,4)]
p=pdir/'animated-three-frame.gif';frames[0].save(p,save_all=True,append_images=frames[1:],duration=[200,300,400],loop=0)
track(p,'Animated GIF: import should be intentional about first-frame semantics; three frames')
p=pdir/'exif-orientation-6.jpg'
ex=Image.Exif();ex[274]=6
base.save(p,quality=91,exif=ex)
track(p,'EXIF orientation 6 means displayed image is rotated clockwise 90 degrees',details={'exif_orientation':6})
p=pdir/'embedded-srgb-profile.jpg'
try:
 profile=ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
 base.save(p,quality=95,icc_profile=profile)
 track(p,'JPEG with embedded sRGB ICC profile')
except Exception as ex:print('SKIP ICC',ex)
# 16-bit grayscale actual pixel values
p=pdir/'16-bit-grayscale.png'
w,h=240,336
im=Image.new('I;16',(w,h));im.putdata([int(((x/w)*65535)) for y in range(h) for x in range(w)])
im.save(p)
track(p,'PNG with 16-bit grayscale samples')
# SVG is deliberately unsupported by ImageIO by default (kept in invalid section)

# 04 DPI metadata, compressibility, actual sample resolution
qdir=ROOT/SECTIONS['quality']
for dpi in (72,150,300,600):
 p=qdir/f'fixed-750x1050-{dpi}dpi.jpg';base.save(p,'JPEG',quality=95,dpi=(dpi,dpi))
 track(p,f'Same 750x1050 pixels; embedded {dpi} DPI changes physical size',details={'pixels':[750,1050],'dpi':dpi})
for wh in [(90,126),(300,420),(750,1050),(1500,2100)]:
 p=qdir/f'pixel-density-{wh[0]}x{wh[1]}-300dpi.png';bitmap(sz=wh).save(p,'PNG',dpi=(300,300))
 track(p,f'Content resolution {wh[0]} x {wh[1]} px with 300 DPI metadata',details={'pixels':list(wh)})
p=qdir/'alpha-soft-edges.png'
im=Image.new('RGBA',(360,504),(0,0,0,0));d=ImageDraw.Draw(im)
for i in range(60,0,-1): d.ellipse((180-2*i,252-2*i,180+2*i,252+2*i),fill=(20,80,140,max(0,255-i*4)))
im.save(p);track(p,'Semi-transparent edges for compositor and PDF alpha tests')
p=qdir/'high-frequency-lines.png';im=Image.new('RGB',(900,1260),'white');d=ImageDraw.Draw(im)
for x in range(0,900,2):d.line((x,0,x,1260),fill='black',width=1)
im.save(p);track(p,'One-pixel alternating lines, tests resampling aliasing')
p=qdir/'jpeg-quality-5.jpg';base.save(p,'JPEG',quality=5)
track(p,'Visible compression artifacts; importer should preserve rather than conceal corruption')

# 05 PDF variants
pdfdir=ROOT/SECTIONS['pdfs']
p=pdfdir/'vector-only.pdf';deck(p,1,'F');track(p,'All vector paths and text; stays crisp at zoom',pages=1)
p=pdfdir/'raster-only.pdf'
new_pdf(p,[{'size':POKER}],lambda c,j,a,s:c.drawImage(ImageReader(bitmap()),0,0,s[0],s[1],mask='auto'))
track(p,'Full-bleed raster embedded in PDF',pages=1)
p=pdfdir/'mixed-vector-raster.pdf'
def mixed(c,j,a,s):
 card(c,2,'F',s);c.drawImage(ImageReader(bitmap(4,(240,336))),29,64,122,125,mask='auto')
new_pdf(p,[{'size':POKER}],mixed);track(p,'Raster inlay with vector text and trim paths',pages=1)
p=pdfdir/'transparency-overprint.pdf'
def transparent(c,j,a,s):
 card(c,4,'F',s)
 c.setFillAlpha(.35);c.setFillColor(HexColor('#B3243F'));c.circle(70,125,57,fill=1,stroke=0)
 c.setFillColor(HexColor('#146B8C'));c.circle(112,125,57,fill=1,stroke=0);c.setFillAlpha(1)
new_pdf(p,[{'size':POKER}],transparent);track(p,'PDF native transparency, overlapping translucent circles',pages=1)
p=pdfdir/'font-embedded.pdf';deck(p,2,'F');track(p,'PDF with embedded fixture TrueType font when available',pages=2)
# PDF rotation metadata; pages retain vector content
p=pdfdir/'page-rotate-90-180-270.pdf'
mem=io.BytesIO();cv=canvas.Canvas(mem,pagesize=POKER,invariant=1)
for n in range(3): card(cv,n,'F');cv.showPage()
cv.save();reader=PdfReader(io.BytesIO(mem.getvalue()));wri=PdfWriter()
for page,deg in zip(reader.pages,(90,180,270)):wri.add_page(page).rotate(deg)
with p.open('wb') as f:wri.write(f)
track(p,'Three cards with Rotate 90/180/270 metadata, not artwork pre-rotated',pages=3,details={'pdf_rotate':[90,180,270]})
p=pdfdir/'mixed-media-page-sizes.pdf'
new_pdf(p,[{'size':sz} for _,sz in SIZE_DEFS[:5]],lambda c,j,a,s:card(c,j,'F',s))
track(p,'Mixed MediaBox dimensions in a single PDF',pages=5)
p=pdfdir/'all-distinct-page-boxes.pdf'
# page boxes are nested: Media >= Crop >= Bleed >= Trim
page_w,page_h=230,310
def box_card(c,j,a,s):
 w,h=s
 c.setFillColor(HexColor('#FCF6E7'));c.rect(0,0,w,h,fill=1,stroke=0)
 guides=[('MEDIA',(0,0,230,310),'#666666'),('CROP',(5,7,225,303),'#164B79'),('BLEED',(12,14,218,296),'#C4653D'),('TRIM',(22,24,208,286),'#29815C'),('ART',(30,36,200,278),'#795180')]
 for name,(x1,y1,x2,y2),color in guides:
  c.setStrokeColor(HexColor(color));c.setLineWidth(1.1)
  c.rect(x1,y1,x2-x1,y2-y1,fill=0)
  c.setFillColor(HexColor(color));c.setFont(FB,7)
  c.drawString(x1+4,y2-8,name)
 c.setFillColor(HexColor('#173D52'));c.setFont(FB,15)
 c.drawCentredString(w/2,h/2+4,'PDF BOX TEST')
 c.setFont(FN,8);c.drawCentredString(w/2,h/2-12,'Five distinct boundaries')
new_pdf(p,[{'size':(page_w,page_h)}],box_card)
r=PdfReader(str(p));wri=PdfWriter();page=r.pages[0]
for field,b in [('mediabox',(0,0,230,310)),('cropbox',(5,7,225,303)),('bleedbox',(12,14,218,296)),('trimbox',(22,24,208,286)),('artbox',(30,36,200,278))]:
 setattr(page,field,RectangleObject([float(v) for v in b]))
wri.add_page(page)
with p.open('wb') as f:wri.write(f)
track(p,'All Media/Crop/Bleed/Trim/Art boxes distinct and correctly nested',pages=1,details={'media':[0,0,230,310],'crop':[5,7,225,303],'bleed':[12,14,218,296],'trim':[22,24,208,286]})
p=pdfdir/'nonzero-mediabox-origin.pdf'
new_pdf(p,[{'size':(270,360)}],lambda c,j,a,s:card(c,5,'F',s))
r=PdfReader(str(p));wri=PdfWriter();page=r.pages[0]
for fld,b in [('mediabox',(16,24,250,336)),('cropbox',(21,29,245,330)),('bleedbox',(26,34,240,325)),('trimbox',(35,43,231,315))]:setattr(page,fld,RectangleObject(list(map(float,b))))
wri.add_page(page)
with p.open('wb') as f:wri.write(f)
track(p,'Every PDF box has nonzero lower-left origin; tests offsets',pages=1,details={'media':[16,24,250,336],'trim':[35,43,231,315]})

# 06 bleed: precise trim/boundaries marked using solid colors
bleeddir=ROOT/SECTIONS['bleed']
def bleed_card(c,j,a,s):
 w,h=s;bl=3*MM;pad=bl+8
 c.setFillColor(HexColor('#B65337'));c.rect(0,0,w,h,fill=1,stroke=0)
 c.setStrokeColor(HexColor('#1B4251'));c.setLineWidth(3);c.rect(bl,bl,w-2*bl,h-2*bl,fill=0)
 c.setFillColor(HexColor('#F4EEDB'));c.rect(bl+9,bl+9,w-2*(bl+9),h-2*(bl+9),fill=1,stroke=0)
 c.setFillColor(HexColor('#173B4C'));c.setFont(FB,11);c.drawCentredString(w/2,h/2+6,'TRIM = BLUE')
 c.setFont(FN,9);c.drawCentredString(w/2,h/2-10,'BLEED = RUST')
 c.setFont(FB,8);c.drawCentredString(w/2,h/2-28,'RED BEYOND TRIM 3 mm')
 # intentional crop-risk micro lettering close to trim
 c.setFont(FN,5.5);c.drawCentredString(w/2,bl+1.5,'TOO CLOSE TO CUT')
p=bleeddir/'3mm-bleed-with-distinct-boxes.pdf'
sz=(POKER[0]+6*MM,POKER[1]+6*MM)
new_pdf(p,[{'size':sz}],bleed_card)
r=PdfReader(str(p));wri=PdfWriter();page=r.pages[0]
page.trimbox=RectangleObject([3*MM,3*MM,sz[0]-3*MM,sz[1]-3*MM]);page.bleedbox=RectangleObject([0,0,sz[0],sz[1]])
page.cropbox=RectangleObject([0,0,sz[0],sz[1]]);wri.add_page(page)
with p.open('wb') as f:wri.write(f)
track(p,'TrimBox is exactly poker size; BleedBox extends by 3mm each edge',pages=1,details={'trim_size_points':list(POKER),'bleed_mm':3})
p=bleeddir/'no-bleed-artwork-to-edge.pdf'
new_pdf(p,[{'size':POKER}],lambda c,j,a,s:(c.setFillColor(HexColor('#C4683F')),c.rect(0,0,*s,fill=1,stroke=0),c.setFont(FB,12),c.setFillColor(white),c.drawCentredString(s[0]/2,s[1]/2,'NO BLEED - EDGE TO EDGE')))
track(p,'Artwork reaches MediaBox edges, but no extra bleed pixels exist',pages=1)
p=bleeddir/'safe-margin-and-hairlines.pdf'
def safe_card(c,j,a,s):
 w,h=s;c.setFillColor(white);c.rect(0,0,w,h,fill=1,stroke=0)
 for offset,color,th in [(0,'#B15B47',.25),(3*MM,'#DBAC53',.35),(6*MM,'#51776F',.5),(12*MM,'#173D52',1)]:
  c.setLineWidth(th);c.setStrokeColor(HexColor(color));c.rect(offset,offset,w-2*offset,h-2*offset)
 c.setFillColor(HexColor('#173D52'));c.setFont(FB,11);c.drawCentredString(w/2,h/2+12,'SAFE ZONES')
 c.setFont(FN,8);c.drawCentredString(w/2,h/2-3,'0 | 3 | 6 | 12 mm')
new_pdf(p,[{'size':POKER}],safe_card)
track(p,'Four safe-margin rectangles and precise hairlines at varying widths',pages=1)

# 07 import sequences: 12 pair IDs, common back; one odd document
impdir=ROOT/SECTIONS['imports']
for name,side in [('separate-fronts-12.pdf','F'),('separate-backs-12.pdf','B')]:
 p=impdir/name;deck(p,12,side);track(p,'Separate '+('front' if side=='F' else 'back')+' document: pages 1-12 correspond by index',pages=12)
ids=[i for i in range(12) for _ in range(2)]
sides=['F' if j%2==0 else 'B' for j in range(24)]
p=impdir/'alternating-front-back-24pages.pdf';mixed_deck(p,ids,sides)
track(p,'Correct F1,B1,F2,B2 ... F12,B12 ordering',pages=24,details={'import_mode':'alternating'})
p=impdir/'first-half-fronts-second-half-backs-24pages.pdf';mixed_deck(p,list(range(12))*2,['F']*12+['B']*12)
track(p,'First 12 pages fronts, next 12 backs',pages=24,details={'import_mode':'first_half_second_half'})
p=impdir/'one-back-repeat-for-every-card.pdf';deck(p,1,'B',theme='art')
track(p,'Single common back for Repeat One Back import',pages=1)
p=impdir/'odd-page-alternating-5pages.pdf';mixed_deck(p,[0,0,1,1,2],['F','B','F','B','F'])
track(p,'Odd alternating PDF: third front has no back; app should warn',pages=5)
p=impdir/'odd-page-split-7pages.pdf';mixed_deck(p,[0,1,2,3,0,1,2],['F']*4+['B']*3)
track(p,'Ambiguous half/half split 7 pages; app should warn, not silently infer',pages=7)

# 08 length boundaries: paired files per size including 54, 55
lend=ROOT/SECTIONS['lengths']
for n in (1,8,9,10,17,18,54,55):
 for side in ('F','B'):
  p=lend/f"{n:02d}-cards-{'fronts' if side=='F' else 'backs'}.pdf";deck(p,n,side)
  track(p,f'{n} {side}-side cards, tests ceil(n/9) sheets',pages=n,details={'pair_count':n,'sheet_count':math.ceil(n/9)})

# 09 file combinations, intentionally reversed correspondence, omissions
pairdir=ROOT/SECTIONS['pairing']
for name,side,ids in [('fronts-10.pdf','F',list(range(10))),('backs-correct-10.pdf','B',list(range(10))),('backs-reversed-10.pdf','B',list(reversed(range(10)))),('backs-only-eight.pdf','B',list(range(8)))]:
 p=pairdir/name;deck(p,len(ids),side,indices=ids)
 track(p,name.replace('-',' ')+'; IDs identify intended pairing',pages=len(ids),details={'pair_ids':[i+1 for i in ids]})
for i in range(3):
 p=pairdir/f'drag-single-front-{i+1:02d}.png';bitmap(i+1).save(p,'PNG');track(p,f'Individual PNG front {i+1}, suitable for dropping into any preview slot')
for i in range(3):
 p=pairdir/f'drag-single-back-{i+1:02d}.pdf';deck(p,1,'B',indices=[i]);track(p,f'Individual PDF back {i+1}, suitable for dropping into any preview slot',pages=1)

# 10 malformed / unsupported / password-protected
bad=ROOT/SECTIONS['invalid']
p=bad/'empty-zero-byte.pdf';p.write_bytes(b'');track(p,'Zero-byte PDF must show an import error',expected='invalid')
p=bad/'truncated-pdf.pdf';p.write_bytes((ROOT/SECTIONS['registration']/'registration-fronts-9.pdf').read_bytes()[:110]);track(p,'Truncated PDF header/object data',expected='invalid')
p=bad/'not-really-a-pdf.pdf';p.write_text('This is deliberately not a PDF file.\n',encoding='utf-8');track(p,'Plain UTF-8 text with misleading PDF extension',expected='invalid')
p=bad/'zero-byte.png';p.write_bytes(b'');track(p,'Zero-byte PNG must show import error',expected='invalid')
p=bad/'jpeg-bytes-named-png.png';p.write_bytes((pdir/'baseline.jpg').read_bytes());track(p,'Mismatched extension and file signature; expected platform-dependent sniffing',expected='ambiguous')
p=bad/'unsupported-svg.svg'
p.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="180" height="252" viewBox="0 0 180 252"><rect width="180" height="252" fill="#173D52"/><text x="90" y="126" fill="white" text-anchor="middle">SVG TEST</text></svg>\n',encoding='utf-8')
track(p,'SVG not in usual ImageIO formats; app should reject gracefully unless SVG is deliberately supported',expected='unsupported')
p=bad/'pdf-with-no-pages.pdf';wri=PdfWriter();
with p.open('wb') as f:wri.write(f)
track(p,'Structurally valid PDF containing zero pages: must reject/warn',expected='zero_pages',pages=0)
p=bad/'password-required.pdf';wri=PdfWriter();r=PdfReader(str(reg_front));wri.add_page(r.pages[0]);wri.encrypt('testpass')
with p.open('wb') as f:wri.write(f)
track(p,'Encrypted PDF with user password testpass; no sensitive content',expected='encrypted',pages=1,details={'password':'testpass'})

# 11 realistic imaginary game deck, coherent printed artwork
art=ROOT/'07-deck-import-patterns'
for side in ('F','B'):
 p=art/('tidal-signal-fronts-12.pdf' if side=='F' else 'tidal-signal-backs-12.pdf')
 deck(p,12,side,theme='art')
 track(p,'Tidal Signal original procedural vector card game; '+side+' pages',pages=12)
p=art/'tidal-signal-alternating-24pages.pdf'
mixed_deck(p,[i for i in range(12) for _ in range(2)],['F','B']*12,theme='art')
track(p,'Realistic fictional deck with F1,B1... interleaving; vector artwork',pages=24)

# tracking manifest, includes immutable checksum
for e in records:
 data=(ROOT/e['path']).read_bytes();e['bytes']=len(data);e['sha256']=hashlib.sha256(data).hexdigest()
records.sort(key=lambda v:v['path'])
manifest={'collection':'PnP-o-matic test fixtures','format_version':1,'generation_seed':20261007,
 'generated_with':'generators/generate.py','card_reference_poker_points':[180,252],
 'duplex_mapping':{'long_edge_back_ids_in_sheet_reading_order':[3,2,1,6,5,4,9,8,7],
                   'short_edge_back_ids_in_sheet_reading_order':[7,8,9,4,5,6,1,2,3]},
 'files':records}
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print('Generated',len(records),'fixtures,',sum(e['bytes'] for e in records)//1024,'KiB')
print('PDFs',sum(e['path'].endswith('.pdf') for e in records),'images',sum(e['path'].lower().endswith(('.jpg','.jpeg','.png','.tiff','.tif','.bmp','.gif','.webp')) for e in records))
