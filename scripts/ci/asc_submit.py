import json,os,glob,hashlib,time,sys;from asc_lib import *
MODE=open("ci-mode").read().strip(); print("MODE",MODE)
VID="d85b8600-f6c7-41e9-90b1-b346acfe54f2"; B5="61e21838-76e2-4de1-a181-6d372bba7103"
LOC={"en-US":"6f59341a-2f1f-4fef-8a9a-d010efc28ba9","zh-Hans":"92b389b1-932b-4ab2-aa22-c4f869d04aa3"}
def p(t,r): print(t, "ERR "+str(r.get("error"))+" "+r.get("body","") if "error" in r else "ok")
def upload(kind,setid,path):
    rel={"appScreenshots":"appScreenshotSet","appPreviews":"appPreviewSet"}[kind]
    data=open(path,"rb").read()
    attrs={"fileName":os.path.basename(path),"fileSize":len(data)}
    if kind=="appPreviews": attrs["mimeType"]="video/mp4"
    r=req("POST",f"/v1/{kind}",{"data":{"type":kind,"attributes":attrs,"relationships":{rel:{"data":{"type":rel+"s","id":setid}}}}})
    if "error" in r: p("create "+path,r); return
    aid=r["data"]["id"]
    for op in r["data"]["attributes"]["uploadOperations"]:
        chunk=data[op["offset"]:op["offset"]+op["length"]]
        hd={h["name"]:h["value"] for h in op.get("requestHeaders",[])}
        x=req(op["method"],None,raw=chunk,headers=hd,url=op["url"]); 
        if "error" in x: p("chunk",x); return
    r2=req("PATCH",f"/v1/{kind}/{aid}",{"data":{"type":kind,"id":aid,"attributes":{"uploaded":True,"sourceFileChecksum":hashlib.md5(data).hexdigest()}}})
    p(f"upload {path} -> {aid}",r2)
def getset(kind,lid,dt):
    attr={"appScreenshotSets":"screenshotDisplayType","appPreviewSets":"previewType"}[kind]
    for s in get(f"/v1/appStoreVersionLocalizations/{lid}/{kind}").get("data",[]):
        if s["attributes"][attr]==dt: return s["id"]
    r=req("POST",f"/v1/{kind}",{"data":{"type":kind,"attributes":{attr:dt},"relationships":{"appStoreVersionLocalization":{"data":{"type":"appStoreVersionLocalizations","id":lid}}}}})
    p(f"create set {kind} {dt}",r); return r.get("data",{}).get("id")
if MODE=="apply":
    p("attach build 5",req("PATCH",f"/v1/appStoreVersions/{VID}/relationships/build",{"data":{"type":"builds","id":B5}}))
    p("releaseType MANUAL",req("PATCH",f"/v1/appStoreVersions/{VID}",{"data":{"type":"appStoreVersions","id":VID,"attributes":{"releaseType":"MANUAL"}}}))
    ta=get(f"/v2/appAvailabilities/{APP}/territoryAvailabilities?limit=200&include=territory")["data"]
    for t in ta:
        tid=t["relationships"]["territory"]["data"]["id"]
        if not t["attributes"]["available"]:
            p("enable "+tid,req("PATCH",f"/v1/territoryAvailabilities/{t['id']}",{"data":{"type":"territoryAvailabilities","id":t["id"],"attributes":{"available":True}}}))
    for loc,lid in LOC.items():
        sid=getset("appScreenshotSets",lid,"APP_IPHONE_67")
        existing=get(f"/v1/appScreenshotSets/{sid}/appScreenshots").get("data",[])
        if existing: print("screenshots exist",loc,len(existing))
        else:
            for f in sorted(glob.glob(f"assets/{loc}/*.png")): upload("appScreenshots",sid,f)
        pid=getset("appPreviewSets",lid,"IPHONE_67")
        if get(f"/v1/appPreviewSets/{pid}/appPreviews").get("data"): print("preview exists",loc)
        else: upload("appPreviews",pid,"assets/preview.mp4")
if MODE in("apply","check","submit"):
    time.sleep(60 if MODE=="apply" else 0)
    v=get(f"/v1/appStoreVersions/{VID}?include=build")["data"]; print("VERSION",v["attributes"]["appStoreState"],v["attributes"]["releaseType"],"build",v["relationships"]["build"]["data"])
    for loc,lid in LOC.items():
        for s in get(f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets").get("data",[]):
            print(loc,"shots",[(x["attributes"]["fileName"],x["attributes"]["assetDeliveryState"]["state"],x["attributes"]["assetDeliveryState"].get("errors")) for x in get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"]])
        for s in get(f"/v1/appStoreVersionLocalizations/{lid}/appPreviewSets").get("data",[]):
            print(loc,"previews",[(x["attributes"]["fileName"],x["attributes"]["assetDeliveryState"]["state"],x["attributes"]["assetDeliveryState"].get("errors")) for x in get(f"/v1/appPreviewSets/{s['id']}/appPreviews")["data"]])
    ta=get(f"/v2/appAvailabilities/{APP}/territoryAvailabilities?limit=200&include=territory")["data"]
    print("UNAVAILABLE",[t["relationships"]["territory"]["data"]["id"] for t in ta if not t["attributes"]["available"]],"of",len(ta))
if MODE=="submit":
    ex=[x for x in get(f"/v1/reviewSubmissions?filter[app]={APP}&filter[state]=READY_FOR_REVIEW").get("data",[])]
    r={"data":ex[0]} if ex else req("POST","/v1/reviewSubmissions",{"data":{"type":"reviewSubmissions","attributes":{"platform":"IOS"},"relationships":{"app":{"data":{"type":"apps","id":APP}}}}})
    p("reviewSubmission",r)
    if "error" not in r:
        rid=r["data"]["id"]
        p("item",req("POST","/v1/reviewSubmissionItems",{"data":{"type":"reviewSubmissionItems","relationships":{"reviewSubmission":{"data":{"type":"reviewSubmissions","id":rid}},"appStoreVersion":{"data":{"type":"appStoreVersions","id":VID}}}}}))
        r3=req("PATCH",f"/v1/reviewSubmissions/{rid}",{"data":{"type":"reviewSubmissions","id":rid,"attributes":{"submitted":True}}})
        p("submit",r3); print("RS",rid,r3.get("data",{}).get("attributes"))
