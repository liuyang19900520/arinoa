import os,time,jwt,json,urllib.request,urllib.error
key=open(os.environ["KEYFILE"]).read()
tok=jwt.encode({"iss":os.environ["ASC_ISSUER_ID"],"iat":int(time.time()),"exp":int(time.time())+1100,"aud":"appstoreconnect-v1"},key,algorithm="ES256",headers={"kid":os.environ["ASC_KEY_ID"],"typ":"JWT"})
B="https://api.appstoreconnect.apple.com"
def call(p,m="GET",body=None):
    r=urllib.request.Request(B+p,method=m,data=json.dumps(body).encode() if body else None,headers={"Authorization":"Bearer "+tok,"Content-Type":"application/json"})
    try:
        x=urllib.request.urlopen(r).read(); return json.loads(x) if x else {"ok":True}
    except urllib.error.HTTPError as e: return {"error":e.code,"body":e.read().decode()[:1500]}
APP="6827531369"
bs=call(f"/v1/builds?filter[app]={APP}&filter[version]=3&include=buildBetaDetail")
print("builds:",[(b["id"],b["attributes"].get("processingState")) for b in bs.get("data",[])] if "data" in bs else bs)
bid=bs["data"][0]["id"]
det={i["type"]:i["attributes"] for i in bs.get("included",[])}.get("buildBetaDetails",{})
print("buildBetaDetail:",det)
grp=[g for g in call(f"/v1/apps/{APP}/betaGroups")["data"] if g["attributes"]["name"]=="Family"][0]
print("add to Family:",call(f"/v1/betaGroups/{grp['id']}/relationships/builds","POST",{"data":[{"type":"builds","id":bid}]}))
ex=call(f"/v1/builds/{bid}/betaAppReviewSubmission")
print("existing submission:",ex)
if not (ex.get("data")) and det.get("externalBuildState")=="READY_FOR_BETA_SUBMISSION":
    print("SUBMIT:",call("/v1/betaAppReviewSubmissions","POST",{"data":{"type":"betaAppReviewSubmissions","relationships":{"build":{"data":{"type":"builds","id":bid}}}}}))
time.sleep(10)
print("after detail:",call(f"/v1/builds/{bid}/buildBetaDetail").get("data",{}).get("attributes"))
print("after submission:",call(f"/v1/builds/{bid}/betaAppReviewSubmission").get("data",{}).get("attributes"))
print("Family builds:",[b["attributes"]["version"] for b in call(f"/v1/betaGroups/{grp['id']}/builds").get("data",[])])
print("== READ-ONLY APP RECORD ==")
a=call(f"/v1/apps/{APP}");print("app:",a.get("data",{}).get("attributes",a))
print("appStoreVersions:",[(v["attributes"].get("versionString"),v["attributes"].get("appStoreState"),v["attributes"].get("platform")) for v in call(f"/v1/apps/{APP}/appStoreVersions").get("data",[])])
for inf in call(f"/v1/apps/{APP}/appInfos").get("data",[]):
    print("appInfo:",inf["attributes"])
    for rel in ["primaryCategory","ageRatingDeclaration"]:
        print(" ",rel,call(f"/v1/appInfos/{inf['id']}/{rel}").get("data"))
    print("  localizations:",[l["attributes"] for l in call(f"/v1/appInfos/{inf['id']}/appInfoLocalizations").get("data",[])])
print("priceSchedule:",call(f"/v1/apps/{APP}/appPriceSchedule"))
print("availability:",call(f"/v2/appAvailabilities/{APP}") )
print("betaAppLocalizations:",[l["attributes"] for l in call(f"/v1/apps/{APP}/betaAppLocalizations").get("data",[])])
print("betaAppReviewDetail:",call(f"/v1/apps/{APP}/betaAppReviewDetail").get("data",{}).get("attributes"))
