import json;from asc_lib import *
def show(t,d): print("==",t,"==");print(json.dumps(d,ensure_ascii=False)[:3000])
a=get(f"/v1/apps/{APP}"); show("app",a.get("data",{}).get("attributes",a))
vs=get(f"/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS")
for v in vs.get("data",[]): print("VERSION",v["id"],json.dumps(v["attributes"],ensure_ascii=False))
vid=[v for v in vs["data"] if v["attributes"]["versionString"]=="1.0.0"][0]["id"]
show("build",get(f"/v1/appStoreVersions/{vid}/build"))
show("reviewDetail",get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail"))
for l in get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]:
    at=l["attributes"]; print("VLOC",l["id"],at["locale"],{k:(at[k] if k not in("description",) else (at[k] or "")[:40]) for k in at})
    for kind in ("appScreenshotSets","appPreviewSets"):
        print("  ",kind,[(s["id"],s["attributes"]) for s in get(f"/v1/appStoreVersionLocalizations/{l['id']}/{kind}").get("data",[])])
for ai in get(f"/v1/apps/{APP}/appInfos?include=primaryCategory")["data"]:
    print("APPINFO",ai["id"],json.dumps(ai["attributes"]),json.dumps(ai["relationships"].get("primaryCategory",{}).get("data")))
    for l in get(f"/v1/appInfos/{ai['id']}/appInfoLocalizations")["data"]: print("  ILOC",l["id"],json.dumps(l["attributes"],ensure_ascii=False))
show("availabilityV2",get(f"/v1/apps/{APP}/appAvailabilityV2"))
av=get(f"/v1/apps/{APP}/appAvailabilityV2").get("data")
if av:
    ta=get(f"/v2/appAvailabilities/{av['id']}/territoryAvailabilities?limit=200&include=territory")
    print("TERR count",len(ta.get("data",[])),"sample",[(t["relationships"]["territory"]["data"]["id"],t["attributes"]) for t in ta.get("data",[]) if t["relationships"]["territory"]["data"]["id"] in("JPN","CHN","USA","KOR")])
    print("TERR available",sorted(t["relationships"]["territory"]["data"]["id"] for t in ta.get("data",[]) if t["attributes"].get("available")))
show("price",get(f"/v1/apps/{APP}/appPriceSchedule?include=baseTerritory,manualPrices"))
show("reviewSubmissions",get(f"/v1/reviewSubmissions?filter[app]={APP}"))
b5=get(f"/v1/builds?filter[app]={APP}&filter[version]=5")
show("build5",[(b["id"],b["attributes"].get("processingState"),b["attributes"].get("usesNonExemptEncryption")) for b in b5.get("data",[])])
