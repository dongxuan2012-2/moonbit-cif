from pathlib import Path
import sys,io,json,subprocess,os,traceback,hashlib,unicodedata,re,ast
import argparse
ap=argparse.ArgumentParser(description='Compare CIF semantic values against PyCifRW and pinned COMCIFS text assertions.')
ap.add_argument('--corpus',type=Path,required=True)
ap.add_argument('--oracle-path',type=Path,required=True)
ap.add_argument('--expectations',type=Path,required=True)
ap.add_argument('--moon',type=Path,default=Path('moon'))
ap.add_argument('--output',type=Path,required=True)
args=ap.parse_args();w=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(args.oracle_path));import CifFile
moon=args.moon;env=os.environ.copy()
def key(s):return unicodedata.normalize('NFD',unicodedata.normalize('NFD',s).casefold())
def normalize(doc):return {key(b):{key(k):v for k,v in fields.items()} for b,fields in doc.items()}
def c_expectations():
 source=args.expectations.read_text(encoding='utf8')
 vals={}
 for name,body in re.findall(r'UChar (value_\w+)\[\] = \{(.*?)\};',source,re.S):
  tokens=re.findall(r"'(?:\\.|[^'\\])*'|0x[0-9a-fA-F]+|\b0\b",body)
  codes=[ord(ast.literal_eval(t)) if t.startswith("'") else int(t,0) for t in tokens]
  vals[name]=''.join(chr(c) for c in codes if c)
 mapping={'_plain1':'value_plain1','_plain2':'value_plain2','_terminators':'value_terminators','_folded1':'value_folded1','_folded2':'value_folded2','_prefixed1':'value_prefixed','_prefixed2':'value_prefixed','_pfx_folded':'value_pfx_folded'}
 out={k:vals[v] for k,v in mapping.items()}
 out.update({k:'' for k in ['_folded_empty','_prefixed_empty','_pfx_fold_empty']})
 return out
results=[]
for path in sorted(args.corpus.glob('*.cif')):
 text=path.read_text(encoding='utf-8-sig');grammar='2.0' if text.startswith('#\\#CIF_2.0') else '1.1'
 try:
  doc=CifFile.ReadCif(io.StringIO(text),grammar=grammar)
  expected={str(b):{str(k):doc[b][k] for k in doc[b].keys()} for b in doc.keys()}
  if path.name=='text_fields.cif': expected={'text_fields':c_expectations()}
  expected=normalize(expected)
 except Exception as e:
  results.append({'sample':path.name,'oracle_error':str(e)});continue
 for backend in ['js','wasm-gc']:
  p=subprocess.run([str(moon),'run','cmd/inspect','--target',backend,'--',text],cwd=w,env=env,capture_output=True,text=True,encoding='utf8')
  rec={'sample':path.name,'target':backend,'exit':p.returncode,'stderr':p.stderr,'stdout':p.stdout}
  try:
   actual=json.loads(p.stdout.strip().splitlines()[-1]);got=normalize({x['name'][5:]:x['fields'] for x in actual['blocks']})
   rec['reference']='COMCIFS pinned C test static assertions' if path.name=='text_fields.cif' else 'PyCifRW 5.0.1';rec['expected']=expected;rec['actual']=got;rec['diagnostics']=actual['diagnostics'];rec['pass']=p.returncode==0 and actual['valid'] and got==expected and actual['original']==text
  except Exception as e:rec['pass']=False;rec['error']=str(e)
  results.append(rec)

# Independent parser rejection checks. Diagnostic wording/coordinates are tested separately.
for label,text,grammar in [
 ('bad_loop','data_x\nloop_\n_a\n_b\n1\n','1.1'),
 ('bad_quote',"data_x\n_a 'missing\n",'1.1'),
 ('bad_text','data_x\n_a\n;missing','1.1'),
 ('bad_list','#\\#CIF_2.0\ndata_x\n_a [ 1 2\n','2.0')]:
 oracle_rejected=False
 try:
  import contextlib
  with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()): CifFile.ReadCif(io.StringIO(text),grammar=grammar)
 except Exception:oracle_rejected=True
 for backend in ['js','wasm-gc']:
  p=subprocess.run([str(moon),'run','cmd/inspect','--target',backend,'--',text],cwd=w,env=env,capture_output=True,text=True,encoding='utf8')
  actual=json.loads(p.stdout.strip().splitlines()[-1])
  results.append({'sample':label,'target':backend,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'oracle_rejected':oracle_rejected,'pass':oracle_rejected and not actual['valid'] and p.returncode==0,'diagnostics':actual['diagnostics']})

args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
for x in results:print(x['sample'],x.get('target'),x.get('pass'),json.dumps(x.get('diagnostics',x.get('oracle_error','')),ensure_ascii=False)[:300])
print('passed',sum(x.get('pass',False) for x in results),'of',len(results))

if any(not x.get("pass",False) for x in results): sys.exit(1)
