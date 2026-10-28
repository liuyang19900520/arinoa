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
AGE_BOOL=["gambling","unrestrictedWebAccess","lootBox","messagingAndChat","parentalControls","ageAssurance","userGeneratedContent","advertising","healthOrWellnessTopics","socialMedia"]
import re
ar=g(f"/v1/appInfos/{IID}/ageRatingDeclaration");aid=ar["data"]["id"]
attrs={k:"NONE" for k in AGE_ENUM}; attrs.update({k:False for k in AGE_BOOL})
for MODE in ("dry","apply"):
  for _ in range(6):
    r=do("ageRatingDeclaration","PATCH",f"/v1/ageRatingDeclarations/{aid}",{"data":{"type":"ageRatingDeclarations","id":aid,"attributes":attrs}})
    if MODE!="apply" or not(isinstance(r,dict) and "error" in r): break
    m=re.search(r"attribute '(\w+)'",r["body"])
    if not m: break
    k=m.group(1); FAIL.pop()
    if "REQUIRED" in r["body"]: print("       adding required:",k,"=false"); attrs[k]=False
    else: print("       dropping rejected:",k); attrs.pop(k,None)
print(json.dumps(g(f"/v1/appInfos/{IID}/ageRatingDeclaration")["data"]["attributes"],indent=1))
print("appInfo ratings:",{k:v for k,v in g(f"/v1/appInfos/{IID}")["data"]["attributes"].items() if "Rating" in k})
print("FAILURES:",FAIL)
