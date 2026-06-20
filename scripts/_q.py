import json, os, sys, urllib.request
REF="eqbyvasteolqyktbqbem"; PAT=os.environ.get("SUPABASE_PAT","")
sql=open(sys.argv[1],encoding="utf-8").read()
req=urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query",
 data=json.dumps({"query":sql}).encode(),method="POST",
 headers={"Authorization":f"Bearer {PAT}","Content-Type":"application/json","User-Agent":"mgmt/1.0","Accept":"application/json"})
d=json.loads(urllib.request.urlopen(req,timeout=120).read().decode())
print(next(iter(d[0].values())) if isinstance(d,list) and d and len(d[0])==1 else json.dumps(d,indent=2))
