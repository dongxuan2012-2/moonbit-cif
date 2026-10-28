from pathlib import Path
import urllib.request,json
w=Path(__file__).resolve().parents[1]
r=w/'work'; (r/'evidence').mkdir(parents=True,exist_ok=True)
text=urllib.request.urlopen('https://www.unicode.org/Public/16.0.0/ucd/CaseFolding.txt').read().decode()
(r/'evidence'/'CaseFolding-16.0.0.txt').write_text(text,encoding='utf8')
m={}
for line in text.splitlines():
 line=line.split('#')[0].strip()
 if not line: continue
 cp,status,seq,*_=map(str.strip,line.split(';'))
 if status in ('C','F'): m[int(cp,16)]=''.join(chr(int(n,16)) for n in seq.split())
lines=['// Generated from Unicode 16.0.0 CaseFolding.txt, C/F mappings. Unicode-3.0 license.','///|','fn full_fold(c : Char) -> String {','  match c.to_int() {']
lines += [f'    {k} => {json.dumps(v,ensure_ascii=False)}' for k,v in sorted(m.items())]
lines += ['    _ => c.to_string()','  }','}','///|','fn name_key(s : String) -> String {','  let first = @normalization.nfd(s)','  let parts = first.to_array().map(full_fold)','  @normalization.nfd(parts.join(""))','}']
(w/'casefold_generated.mbt').write_text('\n'.join(lines)+'\n',encoding='utf8')
