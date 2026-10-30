# Revoke ONLY the listed CI-generated Apple Development certs, after checking each.
import os,time,jwt,json,urllib.request,urllib.error,sys
key=open(os.environ["KEYFILE"]).read()
tok=jwt.encode({"iss":os.environ["ASC_ISSUER_ID"],"iat":int(time.time()),"exp":int(time.time())+1100,"aud":"appstoreconnect-v1"},key,algorithm="ES256",headers={"kid":os.environ["ASC_KEY_ID"],"typ":"JWT"})
B="https://api.appstoreconnect.apple.com"
def req(m,p):
    r=urllib.request.Request(B+p,method=m,headers={"Authorization":"Bearer "+tok})
    try:
        x=urllib.request.urlopen(r).read(); return json.loads(x) if x else {}
    except urllib.error.HTTPError as e: return {"error":e.code,"body":e.read().decode()[:300]}
IDS="2K73XR9M7N 3GNNLTTP7M 7HF8RNGZW9 882Z24W8VZ 98N2N7V2MX 99LW5H72NY BW2QC2LA4N J649Q22CKK YXP4LV667S Z28P2LQBA6".split()
PROTECT={"4385WWT5X3","S5F2T2DST4"}
allc={c["id"]:c["attributes"] for c in req("GET","/v1/certificates?limit=200")["data"]}
print("BEFORE:",[(i,a["certificateType"],a["name"]) for i,a in allc.items()])
for i in IDS:
    a=allc.get(i)
    if i in PROTECT or not a: print("SKIP",i,"missing/protected"); continue
    if a["certificateType"]!="DEVELOPMENT" or a["name"]!="Apple Development: Created via API": print("SKIP",i,"mismatch",a["certificateType"],a["name"]); continue
    r=req("DELETE",f"/v1/certificates/{i}"); print("REVOKE",i,"error" if "error" in r else "ok",r.get("error",""))
print("AFTER:",[(c["id"],c["attributes"]["certificateType"],c["attributes"]["name"],c["attributes"]["expirationDate"]) for c in req("GET","/v1/certificates?limit=200")["data"]])
