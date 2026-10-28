import os,time,jwt,json,urllib.request,urllib.error
key=open(os.environ["KEYFILE"]).read()
tok=jwt.encode({"iss":os.environ["ASC_ISSUER_ID"],"iat":int(time.time()),"exp":int(time.time())+1100,"aud":"appstoreconnect-v1"},key,algorithm="ES256",headers={"kid":os.environ["ASC_KEY_ID"],"typ":"JWT"})
B="https://api.appstoreconnect.apple.com"
def g(p):
    r=urllib.request.Request(B+p,headers={"Authorization":"Bearer "+tok})
    try: return json.load(urllib.request.urlopen(r))
    except urllib.error.HTTPError as e: return {"error":e.code,"body":e.read().decode()[:300]}
APP="6827531369"
d=g(f"/v1/apps/{APP}/builds?include=buildBetaDetail,preReleaseVersion&limit=20")
if "error" in d:
    d=g(f"/v1/builds?filter[app]={APP}&sort=-uploadedDate&include=buildBetaDetail,preReleaseVersion&limit=20")
inc={(i["type"],i["id"]):i["attributes"] for i in d.get("included",[])}
print("== BUILDS ==")
builds=d.get("data",[])
if not builds: print(d)
builds.sort(key=lambda b:b["attributes"].get("uploadedDate",""),reverse=True)
for b in builds:
    a=b["attributes"];r=b.get("relationships",{})
    pv=(r.get("preReleaseVersion",{}).get("data") or {}).get("id");bd=(r.get("buildBetaDetail",{}).get("data") or {}).get("id")
    v=inc.get(("preReleaseVersions",pv),{}).get("version");bb=inc.get(("buildBetaDetails",bd),{})
    print(f"id={b['id']} version={v} build={a.get('version')} uploaded={a.get('uploadedDate')} processing={a.get('processingState')} expired={a.get('expired')} internal={bb.get('internalBuildState')} external={bb.get('externalBuildState')}")
for b in builds[:3]:
    s=g(f"/v1/builds/{b['id']}/betaAppReviewSubmission")
    print(f"betaAppReviewSubmission build {b['attributes'].get('version')}:",(s.get("data") or {}).get("attributes") if "error" not in s else s)
print("== BETA GROUPS ==")
gr=g(f"/v1/apps/{APP}/betaGroups")
if "error" in gr: print(gr)
for x in gr.get("data",[]):
    a=x["attributes"];print(f"group '{a.get('name')}' internal={a.get('isInternalGroup')} publicLink={a.get('publicLinkEnabled')}")
    for b in g(f"/v1/betaGroups/{x['id']}/builds").get("data",[]): print("   build",b["attributes"].get("version"))
    for t in g(f"/v1/betaGroups/{x['id']}/betaTesters?limit=50").get("data",[]):
        ta=t["attributes"];print("   tester",ta.get("email"),ta.get("inviteType"),ta.get("state"))
