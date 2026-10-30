import urllib.parse
# Creates ONE Apple Distribution cert from the committed CSR (public) and two
# App Store profiles. Idempotent: reuses a cert/profile it created before.
import os,time,jwt,json,base64,urllib.request,urllib.error,sys
key=open(os.environ["KEYFILE"]).read()
tok=jwt.encode({"iss":os.environ["ASC_ISSUER_ID"],"iat":int(time.time()),"exp":int(time.time())+1100,"aud":"appstoreconnect-v1"},key,algorithm="ES256",headers={"kid":os.environ["ASC_KEY_ID"],"typ":"JWT"})
B="https://api.appstoreconnect.apple.com"
def req(m,p,body=None):
    r=urllib.request.Request(B+p,method=m,data=json.dumps(body).encode() if body else None,headers={"Authorization":"Bearer "+tok,"Content-Type":"application/json"})
    try: return json.load(urllib.request.urlopen(r))
    except urllib.error.HTTPError as e: print("HTTP",e.code,e.read().decode()[:600]); sys.exit(1)
csr="".join(l for l in open("ci-cert/dist.csr").read().splitlines() if "-----" not in l)
certs=req("GET","/v1/certificates?limit=200&filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION")["data"]
print("existing distribution certs:",[(c["id"],c["attributes"]["name"],c["attributes"]["expirationDate"]) for c in certs])
mine=[c for c in certs if c["attributes"].get("displayName","").startswith("Created via API") or "Yang Liu CI" in c["attributes"].get("name","")]
if os.path.exists("ci-cert/cert_id"):
    cid=open("ci-cert/cert_id").read().strip(); c=req("GET",f"/v1/certificates/{cid}")["data"]
else:
    if certs: print("A distribution cert already exists; refusing to create another. Commit ci-cert/cert_id to reuse."); sys.exit(1)
    c=req("POST","/v1/certificates",{"data":{"type":"certificates","attributes":{"certificateType":"DISTRIBUTION","csrContent":csr}}})["data"]
    print("CREATED cert")
a=c["attributes"]; cid=c["id"]
print("CERT",cid,a["certificateType"],a["name"],"exp",a["expirationDate"],"serial",a["serialNumber"])
open("out/dist.cer","wb").write(base64.b64decode(a["certificateContent"]))
for bid,name,fn in [("QB32SP4F5F","Arinoa App Store CI","arinoa"),("P266MDN85Z","Kage Loop App Store CI","shadowplayer")]:
    ex=[p for p in req("GET",f"/v1/profiles?limit=200&filter[name]={urllib.parse.quote(name)}")["data"] if p["attributes"]["profileState"]=="ACTIVE"]
    p=ex[0] if ex else req("POST","/v1/profiles",{"data":{"type":"profiles","attributes":{"name":name,"profileType":"IOS_APP_STORE"},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":bid}},"certificates":{"data":[{"type":"certificates","id":cid}]}}}})["data"]
    pa=p["attributes"]
    print("PROFILE",p["id"],name,pa["profileType"],pa["profileState"],"exp",pa["expirationDate"],"uuid",pa["uuid"])
    open(f"out/{fn}.mobileprovision","wb").write(base64.b64decode(pa["profileContent"]))
