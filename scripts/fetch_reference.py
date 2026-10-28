from pathlib import Path
import urllib.request,sys,io,json,subprocess,os,hashlib,traceback
import argparse
ap=argparse.ArgumentParser()
ap.add_argument('--out',type=Path,required=True)
args=ap.parse_args();r=args.out;r.mkdir(parents=True,exist_ok=True)
samples=r/'samples';samples.mkdir(exist_ok=True);records=[]
sha='7882c1244bb4f69607561448ac82346f6637015f'
for name in ['list_data','table_data','triple','text_fields','unicode','simple_data','simple_loops','cif1_quoting','complex_data']:
 url=f'https://raw.githubusercontent.com/COMCIFS/cif_api/{sha}/test-data/{name}.cif'
 try:
  data=urllib.request.urlopen(url,timeout=20).read();(samples/(name+'.cif')).write_bytes(data)
  records.append({'file':name+'.cif','url':url,'sha256':hashlib.sha256(data).hexdigest(),'license':'LGPL-3.0-or-later; test-data/README, copyright John C Bollinger'})
 except Exception as e: records.append({'file':name,'download_error':str(e)})
url='https://www.crystallography.net/cod/2002926.cif@301791'
try:
 data=urllib.request.urlopen(url,timeout=25).read();(samples/'cod-2002926.cif').write_bytes(data)
 records.append({'file':'cod-2002926.cif','url':url,'sha256':hashlib.sha256(data).hexdigest(),'license':'COD CC0, retain original authorship header; retrieved snapshot, not latest forever'})
except Exception as e: records.append({'file':'cod-2002926','download_error':str(e)})
(r/'sample-sources.json').write_text(json.dumps(records,indent=2),encoding='utf8')
print(json.dumps(records,indent=2))

url=f'https://raw.githubusercontent.com/COMCIFS/cif_api/{sha}/src/tests/test_parse_text_fields.c'
(r/'comcifs-text-expectations.c').write_bytes(urllib.request.urlopen(url,timeout=20).read())
url=f'https://raw.githubusercontent.com/COMCIFS/cif_api/{sha}/test-data/README'
(r/'COMCIFS-TEST-DATA-LICENSE.txt').write_bytes(urllib.request.urlopen(url,timeout=20).read())

import shutil
product=Path(__file__).resolve().parents[1]
for a,b in [('legacy.cif','cif1.cif'),('lab.cif','cif2.cif')]:shutil.copyfile(product/'fixtures'/a,samples/b)
for f in ['COPYING','COPYING.LESSER']:
 (r/f).write_bytes(urllib.request.urlopen(f'https://raw.githubusercontent.com/COMCIFS/cif_api/{sha}/{f}',timeout=20).read())
