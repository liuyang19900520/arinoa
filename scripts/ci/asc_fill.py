import os,time,jwt,json,urllib.request,urllib.error
key=open(os.environ["KEYFILE"]).read()
def tok(): return jwt.encode({"iss":os.environ["ASC_ISSUER_ID"],"iat":int(time.time()),"exp":int(time.time())+1100,"aud":"appstoreconnect-v1"},key,algorithm="ES256",headers={"kid":os.environ["ASC_KEY_ID"],"typ":"JWT"})
T=tok()
B="https://api.appstoreconnect.apple.com"
def req(m,p,body=None):
    r=urllib.request.Request(B+p,method=m,data=json.dumps(body).encode() if body else None,headers={"Authorization":"Bearer "+T,"Content-Type":"application/json"})
    try:
        x=urllib.request.urlopen(r).read(); return json.loads(x) if x else {}
    except urllib.error.HTTPError as e: return {"error":e.code,"body":e.read().decode()[:1500]}
g=lambda p:req("GET",p)
APP="6827531369"; S="submissions/1.0"
PRIV="https://liuyang19900520.github.io/arinoa/privacy.html"; SUP="https://liuyang19900520.github.io/arinoa/support.html"
LOC={"en-US":"en-US","zh-Hans":"zh-Hans","ja":"ja"}
rd=lambda l,f:open(f"{S}/{l}/{f}.txt",encoding="utf-8").read().strip()
FAIL=[]
def do(label,m,p,body):
    print(f"[PLAN] {label}: {m} {p}\n       {json.dumps(body,ensure_ascii=False)[:900]}")
    if MODE=="apply":
        r=req(m,p,body)
        if isinstance(r,dict) and "error" in r: print(f"[FAIL] {label}: {r}"); FAIL.append((label,r))
        else: print(f"[OK]   {label}")
        return r
ver=[v for v in g(f"/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS")["data"] if v["attributes"]["appStoreState"] in("PREPARE_FOR_SUBMISSION","DEVELOPER_REJECTED","REJECTED","METADATA_REJECTED")][0]
VID=ver["id"]
infos=g(f"/v1/apps/{APP}/appInfos")["data"]
info=[i for i in infos if i["attributes"].get("appStoreState",i["attributes"].get("state")) not in("READY_FOR_SALE","READY_FOR_DISTRIBUTION")] or infos
IID=info[0]["id"]
AGE_ENUM=["alcoholTobaccoOrDrugUseOrReferences","contests","gamblingSimulated","gunsOrOtherWeapons","horrorOrFearThemes","matureOrSuggestiveThemes","medicalOrTreatmentInformation","profanityOrCrudeHumor","sexualContentGraphicAndNudity","sexualContentOrNudity","violenceCartoonOrFantasy","violenceRealistic","violenceRealisticProlongedGraphicOrSadistic"]
AGE_BOOL=["gambling","unrestrictedWebAccess","lootBox","messagingAndChat","parentalControls","ageAssurance","userGeneratedContent","advertising","healthOrWellnessTopics"]
def run():
    do("version 1.0 -> 1.0.0 + copyright","PATCH",f"/v1/appStoreVersions/{VID}",{"data":{"type":"appStoreVersions","id":VID,"attributes":{"versionString":"1.0.0","copyright":"2026 Yang Liu"}}})
    do("primary category","PATCH",f"/v1/appInfos/{IID}",{"data":{"type":"appInfos","id":IID,"relationships":{"primaryCategory":{"data":{"type":"appCategories","id":"PHOTO_AND_VIDEO"}}}}})
    do("contentRightsDeclaration","PATCH",f"/v1/apps/{APP}",{"data":{"type":"apps","id":APP,"attributes":{"contentRightsDeclaration":"DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    # age rating
    ar=g(f"/v1/appInfos/{IID}/ageRatingDeclaration")
    if "error" in ar: print("[FAIL] read ageRatingDeclaration",ar); FAIL.append(("ageRating read",ar))
    else:
        aid=ar["data"]["id"]; cur=ar["data"]["attributes"]; print("       current age attrs keys:",sorted(cur))
        attrs={k:"NONE" for k in AGE_ENUM}; attrs.update({k:False for k in AGE_BOOL})
        for _ in range(8):
            r=do("ageRatingDeclaration","PATCH",f"/v1/ageRatingDeclarations/{aid}",{"data":{"type":"ageRatingDeclarations","id":aid,"attributes":attrs}})
            if MODE!="apply" or not(isinstance(r,dict) and "error" in r): break
            bad=[k for k in list(attrs) if f"'{k}'" in r["body"] or f"/{k}" in r["body"] or f'"{k}"' in r["body"]]
            if not bad: break
            for k in bad: print("       dropping field rejected by API:",k); attrs.pop(k)
            FAIL.pop()
    # appInfo localizations
    ex={x["attributes"]["locale"]:x["id"] for x in g(f"/v1/appInfos/{IID}/appInfoLocalizations")["data"]}
    for l,al in LOC.items():
        a={"name":rd(l,"name"),"subtitle":rd(l,"subtitle"),"privacyPolicyUrl":PRIV}
        if al in ex: do(f"appInfoLoc {al}","PATCH",f"/v1/appInfoLocalizations/{ex[al]}",{"data":{"type":"appInfoLocalizations","id":ex[al],"attributes":a}})
        else: do(f"appInfoLoc {al}","POST","/v1/appInfoLocalizations",{"data":{"type":"appInfoLocalizations","attributes":dict(a,locale=al),"relationships":{"appInfo":{"data":{"type":"appInfos","id":IID}}}}})
    ex={x["attributes"]["locale"]:x["id"] for x in g(f"/v1/appStoreVersions/{VID}/appStoreVersionLocalizations")["data"]}
    for l,al in LOC.items():
        a={"description":rd(l,"description"),"keywords":rd(l,"keywords"),"promotionalText":rd(l,"promotional-text"),"supportUrl":SUP}
        if al in ex: do(f"versionLoc {al}","PATCH",f"/v1/appStoreVersionLocalizations/{ex[al]}",{"data":{"type":"appStoreVersionLocalizations","id":ex[al],"attributes":a}})
        else: do(f"versionLoc {al}","POST","/v1/appStoreVersionLocalizations",{"data":{"type":"appStoreVersionLocalizations","attributes":dict(a,locale=al),"relationships":{"appStoreVersion":{"data":{"type":"appStoreVersions","id":VID}}}}})
    rv={"contactFirstName":"Yang","contactLastName":"Liu","contactPhone":"+81 7048134977","contactEmail":"liuyang19900520@gmail.com","demoAccountRequired":False,"notes":open(f"{S}/review-notes.txt",encoding="utf-8").read().strip()}
    d=g(f"/v1/appStoreVersions/{VID}/appStoreReviewDetail")
    if d.get("data"): do("reviewDetail","PATCH",f"/v1/appStoreReviewDetails/{d['data']['id']}",{"data":{"type":"appStoreReviewDetails","id":d["data"]["id"],"attributes":rv}})
    else: do("reviewDetail","POST","/v1/appStoreReviewDetails",{"data":{"type":"appStoreReviewDetails","attributes":rv,"relationships":{"appStoreVersion":{"data":{"type":"appStoreVersions","id":VID}}}}})
    pp=g(f"/v1/apps/{APP}/appPricePoints?filter[territory]=USA&limit=200")
    free=[p for p in pp.get("data",[]) if float(p["attributes"]["customerPrice"])==0]
    if not free: print("[FAIL] no free price point",str(pp)[:400]); FAIL.append(("price point",pp))
    else:
        do("price schedule FREE (base USA)","POST","/v1/appPriceSchedules",{"data":{"type":"appPriceSchedules","relationships":{"app":{"data":{"type":"apps","id":APP}},"baseTerritory":{"data":{"type":"territories","id":"USA"}},"manualPrices":{"data":[{"type":"appPrices","id":"${p0}"}]}}},"included":[{"type":"appPrices","id":"${p0}","attributes":{"startDate":None},"relationships":{"appPricePoint":{"data":{"type":"appPricePoints","id":free[0]["id"]}}}}]})
    terr=[t["id"] for t in g("/v1/territories?limit=200")["data"]]
    print(f"       territories: {len(terr)}, CHN present={'CHN' in terr}")
    cur=g(f"/v1/apps/{APP}/appAvailabilityV2")
    if cur.get("data"):
        tas=g(f"/v2/appAvailabilities/{cur['data']['id']}/territoryAvailabilities?limit=200&include=territory")
        for t in tas.get("data",[]):
            tid=t["relationships"]["territory"]["data"]["id"]; want=(tid!="CHN")
            if t["attributes"].get("available")!=want: do(f"territory {tid}","PATCH",f"/v1/territoryAvailabilities/{t['id']}",{"data":{"type":"territoryAvailabilities","id":t["id"],"attributes":{"available":want}}})
    else:
        inc=[{"type":"territoryAvailabilities","id":"${"+t+"}","attributes":{"available":t!="CHN"},"relationships":{"territory":{"data":{"type":"territories","id":t}}}} for t in terr]
        body={"data":{"type":"appAvailabilities","attributes":{"availableInNewTerritories":True},"relationships":{"app":{"data":{"type":"apps","id":APP}},"territoryAvailabilities":{"data":[{"type":"territoryAvailabilities","id":i["id"]} for i in inc]}}},"included":inc}
        do(f"availability v2 ({len(terr)-1} on, CHN off)","POST","/v2/appAvailabilities",body)
for MODE in ("dry","apply"):
    print(f"\n==================== {MODE.upper()} ====================")
    if MODE=="apply": T=tok()
    run()
print("\n==================== READ BACK ====================")
pj=lambda x:print(json.dumps(x,ensure_ascii=False,indent=1)[:3000])
v=g(f"/v1/appStoreVersions/{VID}?include=build");a=v["data"]["attributes"];print("version:",{k:a.get(k) for k in("versionString","appStoreState","copyright","releaseType")},"build:",(v["data"]["relationships"].get("build",{}).get("data")))
print("app:",{k:g(f"/v1/apps/{APP}")["data"]["attributes"].get(k) for k in("name","primaryLocale","contentRightsDeclaration","isOrEverWasMadeForKids")})
print("primaryCategory:",g(f"/v1/appInfos/{IID}/primaryCategory").get("data"),"secondary:",g(f"/v1/appInfos/{IID}/secondaryCategory").get("data"))
print("ageRating:");pj(g(f"/v1/appInfos/{IID}/ageRatingDeclaration").get("data",{}).get("attributes"))
print("appInfo state/ageRating:",{k:info[0]["attributes"].get(k) for k in info[0]["attributes"]})
for x in g(f"/v1/appInfos/{IID}/appInfoLocalizations")["data"]: print("appInfoLoc",x["attributes"])
for x in g(f"/v1/appStoreVersions/{VID}/appStoreVersionLocalizations")["data"]:
    a=x["attributes"];print("versionLoc",a["locale"],{k:(a.get(k)[:60]+"…" if k=="description" and a.get(k) else a.get(k)) for k in("description","keywords","promotionalText","supportUrl","marketingUrl","whatsNew")})
print("reviewDetail:",g(f"/v1/appStoreVersions/{VID}/appStoreReviewDetail").get("data",{}).get("attributes"))
ps=g(f"/v1/apps/{APP}/appPriceSchedule?include=baseTerritory,manualPrices");print("priceSchedule:",ps.get("data",{}).get("relationships",{}).get("baseTerritory"), [i["attributes"] for i in ps.get("included",[]) if i["type"]=="appPrices"] if "error" not in ps else ps)
mp=g(f"/v1/appPriceSchedules/{APP}/manualPrices?include=appPricePoint,territory");print("manualPrices:",[(i["type"],i["attributes"]) for i in mp.get("included",[])] if "error" not in mp else mp)
av=g(f"/v1/apps/{APP}/appAvailabilityV2")
if av.get("data"):
    print("availability:",av["data"]["attributes"])
    tas=g(f"/v2/appAvailabilities/{av['data']['id']}/territoryAvailabilities?limit=200&include=territory")
    on=[t["relationships"]["territory"]["data"]["id"] for t in tas.get("data",[]) if t["attributes"].get("available")]
    off=[t["relationships"]["territory"]["data"]["id"] for t in tas.get("data",[]) if not t["attributes"].get("available")]
    print(f"territories available={len(on)} unavailable={off}")
else: print("availability:",av)
bl=g(f"/v1/builds?filter[app]={APP}&sort=-uploadedDate&limit=5&include=preReleaseVersion")
print("builds:",[(b["attributes"]["version"],b["attributes"]["processingState"],b["attributes"]["uploadedDate"]) for b in bl.get("data",[])])
print("\nFAILURES:",len(FAIL))
for l,r in FAIL: print(" -",l,r)
