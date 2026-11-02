import os,sys,time,jwt,json,hashlib,requests
MODE=sys.argv[1].strip(); print("MODE",MODE)
key=open(os.environ["KEYFILE"]).read()
def tok(): return jwt.encode({"iss":os.environ["ASC_ISSUER_ID"],"iat":int(time.time()),"exp":int(time.time())+1100,"aud":"appstoreconnect-v1"},key,algorithm="ES256",headers={"kid":os.environ["ASC_KEY_ID"],"typ":"JWT"})
B="https://api.appstoreconnect.apple.com"
def call(m,p,body=None):
    r=requests.request(m,B+p,headers={"Authorization":"Bearer "+tok()},json=body)
    if r.status_code>=300: return {"error":r.status_code,"body":r.text[:800]}
    return r.json() if r.text else {}
def D(r): return r.get("data",[]) if "error" not in r else (print("ERR",r) or [])
APP="6827531369"; VS="1.0.2"; BN="7"
WN={"en":"Minor improvements.","zh":"细节优化","ja":"細かな改善を行いました。","ko":"사소한 개선 사항.","default":"Minor improvements."}
def wn(loc):
    for k in WN:
        if loc.startswith(k): return WN[k]
    return WN["default"]
def build():
    bs=D(call("GET",f"/v1/builds?filter[app]={APP}&filter[version]={BN}&filter[preReleaseVersion.version]={VS}&limit=5"))
    for b in bs: a=b["attributes"]; print("BUILD",b["id"],a.get("version"),a.get("processingState"),"enc",a.get("usesNonExemptEncryption"),"expired",a.get("expired"))
    return bs[0] if bs else None
def versions():
    out={}
    for v in D(call("GET",f"/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=10&include=build")):
        a=v["attributes"];print("VERSION",v["id"],a.get("versionString"),a.get("appStoreState"),a.get("releaseType"),"build",(v["relationships"]["build"].get("data") or {}).get("id"))
        out[a["versionString"]]=v
    return out
def listing(vid):
    sets={}
    for l in D(call("GET",f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")):
        loc=l["attributes"]["locale"]; print("LOC",loc,"whatsNew=",repr(l["attributes"].get("whatsNew")))
        for s in D(call("GET",f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets")):
            if s["attributes"]["screenshotDisplayType"]=="APP_IPHONE_67": sets[loc]=s["id"]
            shots=D(call("GET",f"/v1/appScreenshotSets/{s['id']}/appScreenshots?limit=20"))
            print("SET",loc,s["attributes"]["screenshotDisplayType"],len(shots),[(x["attributes"]["fileName"],(x["attributes"].get("assetDeliveryState") or {}).get("state")) for x in shots])
        for p in D(call("GET",f"/v1/appStoreVersionLocalizations/{l['id']}/appPreviewSets")):
            print("PREVIEWSET",loc,p["attributes"]["previewType"],len(D(call("GET",f"/v1/appPreviewSets/{p['id']}/appPreviews"))))
    return sets
b=build(); vs=versions()
for s in D(call("GET",f"/v1/reviewSubmissions?filter[app]={APP}&limit=10")): print("REVIEWSUB",s["id"],s["attributes"].get("state"),s["attributes"].get("submittedDate"))
if MODE=="status":
    for _ in range(40):
        if b and b["attributes"]["processingState"]=="VALID": break
        time.sleep(30); b=build()
    if VS in vs: listing(vs[VS]["id"])
    sys.exit(0)
if not b or b["attributes"]["processingState"]!="VALID": print("BUILD NOT VALID, stop"); sys.exit(1)
if MODE=="create":
    if VS not in vs:
        r=call("POST","/v1/appStoreVersions",{"data":{"type":"appStoreVersions","attributes":{"platform":"IOS","versionString":VS,"releaseType":"MANUAL"},"relationships":{"app":{"data":{"type":"apps","id":APP}}}}})
        print("CREATE VERSION","ERR "+json.dumps(r) if "error" in r else r["data"]["id"])
        if "error" in r: sys.exit(1)
        vs=versions()
    vid=vs[VS]["id"]
    print("ATTACH",call("PATCH",f"/v1/appStoreVersions/{vid}/relationships/build",{"data":{"type":"builds","id":b["id"]}}) or "ok")
    for l in D(call("GET",f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")):
        if not l["attributes"].get("whatsNew"):
            r=call("PATCH",f"/v1/appStoreVersionLocalizations/{l['id']}",{"data":{"type":"appStoreVersionLocalizations","id":l["id"],"attributes":{"whatsNew":wn(l["attributes"]["locale"])}}})
            print("WHATSNEW",l["attributes"]["locale"],"ERR "+json.dumps(r) if "error" in r else "ok")
    versions(); listing(vid); sys.exit(0)
vid=vs[VS]["id"]
if MODE=="replace":
    sets=listing(vid)
    for loc in ["en-US","zh-Hans"]:
        sid=sets[loc]; old=[x["id"] for x in D(call("GET",f"/v1/appScreenshotSets/{sid}/appScreenshots?limit=20"))]
        print("OLD",loc,len(old))
        for o in old:
            r=call("DELETE",f"/v1/appScreenshots/{o}"); print("DELETE",loc,"ERR "+json.dumps(r) if "error" in r else "ok")
            if "error" in r: sys.exit(1)
        new=[]
        for i in range(1,6):
            fn=f"promo/{loc}/0{i}.png"; data=open(fn,"rb").read()
            r=call("POST","/v1/appScreenshots",{"data":{"type":"appScreenshots","attributes":{"fileName":f"0{i}.png","fileSize":len(data)},"relationships":{"appScreenshotSet":{"data":{"type":"appScreenshotSets","id":sid}}}}})
            if "error" in r: print("CREATE REFUSED",loc,i,r); sys.exit(1)
            sh=r["data"]; new.append(sh["id"])
            for op in sh["attributes"]["uploadOperations"]:
                requests.request(op["method"],op["url"],headers={h["name"]:h["value"] for h in op["requestHeaders"]},data=data[op["offset"]:op["offset"]+op["length"]]).raise_for_status()
            r=call("PATCH",f"/v1/appScreenshots/{sh['id']}",{"data":{"type":"appScreenshots","id":sh["id"],"attributes":{"uploaded":True,"sourceFileChecksum":hashlib.md5(data).hexdigest()}}})
            print("COMMIT",loc,i,"ERR "+json.dumps(r) if "error" in r else "ok")
        print("ORDER",loc,call("PATCH",f"/v1/appScreenshotSets/{sid}/relationships/appScreenshots",{"data":[{"type":"appScreenshots","id":n} for n in new]}) or "ok")
    for _ in range(40):
        time.sleep(15); st=[]
        for loc in ["en-US","zh-Hans"]: st+=[(x["attributes"].get("assetDeliveryState") or {}).get("state") for x in D(call("GET",f"/v1/appScreenshotSets/{sets[loc]}/appScreenshots"))]
        print("STATES",st)
        if all(s=="COMPLETE" for s in st): break
    print("FINAL"); listing(vid); sys.exit(0)
if MODE=="delpreview":
    for l in D(call("GET",f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")):
        loc=l["attributes"]["locale"]
        if loc not in ["en-US","zh-Hans"]: continue
        for p in D(call("GET",f"/v1/appStoreVersionLocalizations/{l['id']}/appPreviewSets")):
            for x in D(call("GET",f"/v1/appPreviewSets/{p['id']}/appPreviews?limit=20")):
                r=call("DELETE",f"/v1/appPreviews/{x['id']}"); print("DELPREVIEW",loc,p["attributes"]["previewType"],x["attributes"].get("fileName"),"ERR "+json.dumps(r) if "error" in r else "ok")
                if "error" in r: sys.exit(1)
    print("FINAL"); listing(vid); sys.exit(0)
if MODE=="submit":
    listing(vid)
    ex=D(call("GET",f"/v1/reviewSubmissions?filter[app]={APP}&filter[state]=READY_FOR_REVIEW"))
    r={"data":ex[0]} if ex else call("POST","/v1/reviewSubmissions",{"data":{"type":"reviewSubmissions","attributes":{"platform":"IOS"},"relationships":{"app":{"data":{"type":"apps","id":APP}}}}})
    if "error" in r: print("RS ERR",r); sys.exit(1)
    rid=r["data"]["id"]; print("RS",rid)
    r=call("POST","/v1/reviewSubmissionItems",{"data":{"type":"reviewSubmissionItems","relationships":{"reviewSubmission":{"data":{"type":"reviewSubmissions","id":rid}},"appStoreVersion":{"data":{"type":"appStoreVersions","id":vid}}}}})
    print("ITEM","ERR "+json.dumps(r) if "error" in r else "ok")
    r=call("PATCH",f"/v1/reviewSubmissions/{rid}",{"data":{"type":"reviewSubmissions","id":rid,"attributes":{"submitted":True}}})
    print("SUBMIT","ERR "+json.dumps(r) if "error" in r else r["data"]["attributes"])
    time.sleep(30); versions()
    for s in D(call("GET",f"/v1/reviewSubmissions?filter[app]={APP}&limit=10")): print("REVIEWSUB",s["id"],s["attributes"].get("state"))
if MODE=="info":
    a=call("GET",f"/v1/apps/{APP}"); print("primaryLocale",a.get("data",{}).get("attributes",{}).get("primaryLocale"))
    for v in D(call("GET",f"/v1/apps/{APP}/appStoreVersions?filter[versionString]={VS}")):
        print("VER",v["id"],v["attributes"].get("appStoreState"),v["attributes"].get("platform"))
        for l in D(call("GET",f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50")):
            lid=l["id"]; loc=l["attributes"]["locale"]
            ss=D(call("GET",f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets?limit=50"))
            ps=D(call("GET",f"/v1/appStoreVersionLocalizations/{lid}/appPreviewSets?limit=50"))
            det=[]
            for s in ss:
                n=len(D(call("GET",f"/v1/appScreenshotSets/{s['id']}/appScreenshots?limit=50")))
                det.append(f"{s['attributes']['screenshotDisplayType']}:{n}")
            print("LOC",loc,"sets",len(ss),det,"previewSets",len(ps))
    r=call("GET",f"/v1/apps/{APP}/appAvailabilityV2")
    aid=r.get("data",{}).get("id"); print("avail",aid,r.get("data",{}).get("attributes"), r.get("error"))
    if aid:
        t=call("GET",f"/v2/appAvailabilities/{aid}/territoryAvailabilities?limit=200&include=territory")
        for x in D(t):
            if x.get("relationships",{}).get("territory",{}).get("data",{}).get("id")=="JPN": print("JPN",x["attributes"])
        print("territories",len(D(t)))
