import os,time,jwt,json,urllib.request,urllib.error
key=open(os.environ["KEYFILE"]).read()
tok=jwt.encode({"iss":os.environ["ASC_ISSUER_ID"],"iat":int(time.time()),"exp":int(time.time())+1100,"aud":"appstoreconnect-v1"},key,algorithm="ES256",headers={"kid":os.environ["ASC_KEY_ID"],"typ":"JWT"})
B="https://api.appstoreconnect.apple.com"
def g(p):
    r=urllib.request.Request(B+p,headers={"Authorization":"Bearer "+tok})
    try: return json.load(urllib.request.urlopen(r))
    except urllib.error.HTTPError as e: return {"error":e.code,"body":e.read().decode()[:300]}
# READ-ONLY: GET only.
print("== CERTIFICATES ==")
c=g("/v1/certificates?limit=200&fields[certificates]=name,certificateType,displayName,expirationDate,platform,serialNumber,activated")
if "error" in c: print(c)
for x in c.get("data",[]):
    a=x["attributes"];print(x["id"],a.get("certificateType"),"|",a.get("displayName"),"|",a.get("name"),"| exp",a.get("expirationDate"),"| serial",a.get("serialNumber"),"| active",a.get("activated"))
print("== PROFILES ==")
p=g("/v1/profiles?limit=200&fields[profiles]=name,profileType,profileState,createdDate,expirationDate,bundleId,certificates&include=bundleId,certificates")
if "error" in p: print(p)
for x in p.get("data",[]):
    a=x["attributes"];r=x.get("relationships",{})
    print(x["id"],a.get("profileType"),a.get("profileState"),"|",a.get("name"),"| created",a.get("createdDate"),"| exp",a.get("expirationDate"),"| certs",[i["id"] for i in r.get("certificates",{}).get("data",[]) or []])
print("== BUNDLE IDS ==")
for x in g("/v1/bundleIds?limit=50").get("data",[]): print(x["id"],x["attributes"].get("identifier"),x["attributes"].get("name"))
