"""Grade pilot answers. Usage: python3 grade.py answers/*.json"""
import json, sys, re, pathlib

PERM = {"Q1":"NO","Q2":"YES","Q3":"NO","Q4":"YES","Q5":"NO","Q6":"NO","Q7":"YES","Q8":"dev",
        "Q9":"YES","Q10":"NO","Q11":"NO"}
AE, SH, SRE, SUE = "AccessExclusiveLock","ShareLock","ShareRowExclusiveLock","ShareUpdateExclusiveLock"
# (lock, rewrite, scan) measured on PostgreSQL 17.11 in Docker (see pg_probe.sh)
PG = {"P01":(AE,False,False),"P02":(AE,True,True),"P03":(AE,False,False),"P04":(AE,True,True),
      "P05":(AE,False,False),"P06":(AE,True,True),"P07":(AE,False,False),"P08":(AE,True,True),
      "P09":(AE,False,False),"P10":(SUE,False,True),"P11":(AE,False,False),"P12":(AE,False,True),
      "P13":(SRE,False,False),"P14":(AE,True,True),"P15":(AE,False,False),"P16":(SH,False,True),
      "P17":(AE,False,False),"P18":(AE,False,False),"P19":(AE,True,True),"P20":("ERROR",None,None)}
A,B = "ALLOW","BLOCK"
NETPOL = dict(zip([f"N{i:02d}" for i in range(1,21)],
   [A,B,B,A,B,A,B,B,A,A,B,B,B,A,B,A,B,A,B,A]))

def load(p):
    t = pathlib.Path(p).read_text()
    m = re.search(r"\{.*\}", t, re.S)
    return json.loads(m.group(0))

def grade(ans):
    out = {}
    pa = ans.get("PERM",{})
    perm_ok = [str(pa.get(k,"")).strip().lower()==v.lower() for k,v in PERM.items()]
    out["PERM"] = (sum(perm_ok), len(perm_ok), [k for k,o in zip(PERM,perm_ok) if not o])
    pg = ans.get("PG",{}); ok=0; n=0; miss=[]
    for k,(l,r,s) in PG.items():
        a = pg.get(k,{}) or {}
        if l=="ERROR":
            n+=1; g = str(a.get("lock","")).upper()=="ERROR"; ok+=g
            if not g: miss.append(f"{k}.lock")
            continue
        for f,exp in (("lock",l),("rewrite",r),("scan",s)):
            n+=1; got=a.get(f)
            g = (str(got).replace(" ","").lower()==exp.lower()) if f=="lock" else (got is exp)
            ok+=g
            if not g: miss.append(f"{k}.{f}={got}")
    out["PG"]=(ok,n,miss)
    na = ans.get("NETPOL",{})
    np_ok=[str(na.get(k,"")).upper()==v for k,v in NETPOL.items()]
    out["NETPOL"]=(sum(np_ok),len(np_ok),[k for k,o in zip(NETPOL,np_ok) if not o])
    return out

if __name__=="__main__":
    for p in sys.argv[1:]:
        g = grade(load(p))
        print(pathlib.Path(p).stem)
        for t,(ok,n,miss) in g.items():
            print(f"  {t:7s} {ok}/{n}  miss={miss}")
