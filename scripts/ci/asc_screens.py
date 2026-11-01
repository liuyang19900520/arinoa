import os,sys,time,jwt,json,hashlib,requests
MODE=sys.argv[1].strip()
key=open(os.environ["KEYFILE"]).read()
def tok(): return jwt.encode({"iss":os.environ["ASC_ISSUER_ID"],"iat":int(time.time()),"exp":int(time.time())+1100,"aud":"appstoreconnect-v1"},key,algorithm="ES256",headers={"kid":os.environ["ASC_KEY_ID"],"typ":"JWT"})
B="https://api.appstoreconnect.apple.com"
def call(m,p,body=None):
    r=requests.request(m,B+p,headers={"Authorization":"Bearer "+tok()},json=body)
    if r.status_code>=300: return {"error":r.status_code,"body":r.text[:600]}
    return r.json() if r.text else {}
APP="6827531369"
vs=call("GET",f"/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=10")
ver=None
for v in vs.get("data",[]):
    a=v["attributes"];print("VERSION",v["id"],a.get("versionString"),a.get("appStoreState"),a.get("appVersionState"),a.get("releaseType"))
    if a.get("versionString")=="1.0.0": ver=v
rs=call("GET",f"/v1/reviewSubmissions?filter[app]={APP}&limit=10")
for s in rs.get("data",[]) if "error" not in rs else [rs]: print("REVIEWSUB",s.get("id"),json.dumps(s.get("attributes",s)))
state=ver["attributes"].get("appStoreState")
locs=call("GET",f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")["data"]
sets={}
def listing():
    for l in locs:
        loc=l["attributes"]["locale"]
        for s in call("GET",f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets")["data"]:
            if s["attributes"]["screenshotDisplayType"]=="APP_IPHONE_67": sets[loc]=s["id"]
            shots=call("GET",f"/v1/appScreenshotSets/{s['id']}/appScreenshots?limit=20")["data"]
            print("SET",loc,s["attributes"]["screenshotDisplayType"],len(shots),[(x["attributes"]["fileName"],(x["attributes"].get("assetDeliveryState") or {}).get("state")) for x in shots])
        for p in call("GET",f"/v1/appStoreVersionLocalizations/{l['id']}/appPreviewSets")["data"]:
            pv=call("GET",f"/v1/appPreviewSets/{p['id']}/appPreviews")["data"]
            print("PREVIEWSET",loc,p["attributes"]["previewType"],len(pv))
listing()
if MODE!="replace" or state=="IN_REVIEW": sys.exit(0)
for loc in ["en-US","zh-Hans"]:
    sid=sets.get(loc); old=[x["id"] for x in call("GET",f"/v1/appScreenshotSets/{sid}/appScreenshots?limit=20")["data"]]
    new=[]
    for i in range(1,6):
        fn=f"promo/{loc}/0{i}.png"; data=open(fn,"rb").read()
        r=call("POST","/v1/appScreenshots",{"data":{"type":"appScreenshots","attributes":{"fileName":f"0{i}.png","fileSize":len(data)},"relationships":{"appScreenshotSet":{"data":{"type":"appScreenshotSets","id":sid}}}}})
        if "error" in r: print("CREATE REFUSED",loc,r); sys.exit(1 if not new else 2)
        sh=r["data"]; new.append(sh["id"])
        for op in sh["attributes"]["uploadOperations"]:
            requests.request(op["method"],op["url"],headers={h["name"]:h["value"] for h in op["requestHeaders"]},data=data[op["offset"]:op["offset"]+op["length"]]).raise_for_status()
        r=call("PATCH",f"/v1/appScreenshots/{sh['id']}",{"data":{"type":"appScreenshots","id":sh["id"],"attributes":{"uploaded":True,"sourceFileChecksum":hashlib.md5(data).hexdigest()}}})
        print("COMMIT",loc,i,"error" in r and r or "ok")
    for o in old: print("DELETE",loc,o,call("DELETE",f"/v1/appScreenshots/{o}"))
    print("ORDER",loc,call("PATCH",f"/v1/appScreenshotSets/{sid}/relationships/appScreenshots",{"data":[{"type":"appScreenshots","id":n} for n in new]}))
for _ in range(30):
    time.sleep(10); st=[]
    for loc in ["en-US","zh-Hans"]:
        st+=[(x["attributes"].get("assetDeliveryState") or {}).get("state") for x in call("GET",f"/v1/appScreenshotSets/{sets[loc]}/appScreenshots")["data"]]
    if all(s=="COMPLETE" for s in st): break
print("FINAL"); listing()
