#!/usr/bin/env python3
"""Check fixture integrity, PDF page counts/boxes, image metadata, and duplex ordering."""
from pathlib import Path
from collections import Counter
import hashlib, json, math, re, sys
from PIL import Image, UnidentifiedImageError
from pypdf import PdfReader
import fitz
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'manifest.json').read_text())
issues=[];passed=0

def check(value,message):
 global passed
 if value:passed+=1
 else:issues.append(message)

def close_rect(rect,vals):return all(abs(float(a)-float(b))<0.02 for a,b in zip(rect,vals))

for item in manifest['files']:
 p=ROOT/item['path'];k=item['expected']
 check(p.is_file(),f'Missing: {p}')
 if not p.exists():continue
 check(hashlib.sha256(p.read_bytes()).hexdigest()==item['sha256'],f'Checksum mismatch {p}')
 is_pdf=p.suffix=='.pdf'
 if k=='unsupported':
  check(p.suffix=='.svg' and p.read_text().startswith('<svg'),f'SVG fixture malformed: {p}')
  continue
 if is_pdf:
  if k=='invalid':
   try:
    PdfReader(p).pages[0];issues.append(f'Invalid PDF unexpectedly read: {p}')
   except Exception:passed+=1
   continue
  try:r=PdfReader(p)
  except Exception as ex:issues.append(f'PDF invalid: {p}: {ex}');continue
  if k=='encrypted':
   check(r.is_encrypted,f'Encryption missing: {p}')
   check(r.decrypt(item['details']['password'])!=0,f'Wrong password: {p}')
  else:check(not r.is_encrypted,f'Unexpectedly encrypted: {p}')
  check(len(r.pages)==item['pdf_pages'],f'Page count mismatch: {p}, got {len(r.pages)} expected {item["pdf_pages"]}')
  if k=='zero_pages':continue
  if 'size_points' in item.get('details',{}):
   check(close_rect([float(r.pages[0].mediabox.width),float(r.pages[0].mediabox.height)],item['details']['size_points']),f'Source size mismatch: {p}')
  if 'pdf_rotate' in item.get('details',{}):
   check([v.get('/Rotate',0) for v in r.pages]==item['details']['pdf_rotate'],f'Rotation mismatch: {p}')
  for fld in ('media','crop','trim','bleed'):
   if fld in item.get('details',{}):
    check(close_rect(list(getattr(r.pages[0],fld+'box')),item['details'][fld]),f'{fld} box mismatch: {p}')
  if 'trim_size_points' in item.get('details',{}):
   box=r.pages[0].trimbox
   check(close_rect([float(box.width),float(box.height)],item['details']['trim_size_points']),f'Bleed trim dimension mismatch: {p}')
  try:
   with fitz.open(p) as doc:
    if doc.needs_pass:doc.authenticate(item['details']['password'])
    if len(doc)>0:
     page=doc[0]; pix=page.get_pixmap(matrix=fitz.Matrix(.3,.3),alpha=False)
     check(pix.width>0 and pix.height>0,f'Page render failed: {p}')
  except Exception as ex:issues.append(f'PDF render error {p}: {ex}')
 elif k=='invalid':
  try:
   with Image.open(p) as im:im.verify();issues.append(f'Invalid image unexpectedly decoded: {p}')
  except Exception:passed+=1
 elif k in ('valid','ambiguous'):
  try:
   with Image.open(p) as im:
    im.verify()
   with Image.open(p) as im:
    if k=='ambiguous':check(im.format=='JPEG',f'Mismatched-extension sample not JPEG signature: {p}')
    if 'pixels' in item.get('details',{}):check(list(im.size)==item['details']['pixels'],f'Image dimensions wrong: {p}')
    if 'dpi' in item.get('details',{}):
     check(all(abs(v-item['details']['dpi'])<2 for v in im.info.get('dpi',(0,0))),f'Image DPI wrong: {p}')
    if 'exif_orientation' in item.get('details',{}):check(im.getexif().get(274)==6,f'EXIF rotation wrong: {p}')
  except Exception as ex:issues.append(f'Image failed to decode: {p}: {ex}')

# Confirm spatial duplex ordering by reading text within the 9 individual slots.
for fmt in ('letter','a4'):
 for flip in ('long','short'):
  p=ROOT/f'reference-outputs/{fmt}-{flip}-edge-expected-9up.pdf'
  with fitz.open(p) as doc:
   check(len(doc)==2,f'Expected two ref pages: {p}')
   for n,expected in enumerate(([1,2,3,4,5,6,7,8,9],manifest['duplex_mapping'][f'{flip}_edge_back_ids_in_sheet_reading_order'])):
    pairs=[]
    for b in doc[n].get_text('blocks'):
     hit=re.search(r'PAIR\s+(\d{2})',b[4])
     if hit:pairs.append((b[1],b[0],int(hit.group(1))))
    ordered=[id for y,x,id in sorted(pairs,key=lambda v:(round(v[0]/100),v[1]))]
    check(ordered==expected,f'Duplex mapping {p} page {n+1}: {ordered} vs {expected}')
    check(len(pairs)==9,f'Expected 9 card markers: {p} page {n+1}')

# Specifically check distinct boxes are nested and distinct.
r=PdfReader(ROOT/'05-pdf-variations/all-distinct-page-boxes.pdf');page=r.pages[0]
for outer,inner in [(page.mediabox,page.cropbox),(page.cropbox,page.bleedbox),(page.bleedbox,page.trimbox)]:
 check(all(float(outer[i])<float(inner[i]) for i in (0,1)) and all(float(outer[i])>float(inner[i]) for i in (2,3)),'Nested PDF boxes incorrect')

c=Counter(v['expected'] for v in manifest['files'])
print(f"Fixtures: {len(manifest['files'])}; checks passed: {passed}; failures: {len(issues)}")
print('Expectations:',dict(c))
if issues:
 for msg in issues:print('FAIL:',msg)
 sys.exit(1)
print('PASS: checksums, PDF counts/boxes, raster decode, metadata and four duplex reference mappings')
