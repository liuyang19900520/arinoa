import os,time,jwt,json,urllib.request,urllib.error
key=open(os.environ["KEYFILE"]).read()
def _tok():
    return jwt.encode({"iss":os.environ["ASC_ISSUER_ID"],"iat":int(time.time()),"exp":int(time.time())+1100,"aud":"appstoreconnect-v1"},key,algorithm="ES256",headers={"kid":os.environ["ASC_KEY_ID"],"typ":"JWT"})
B="https://api.appstoreconnect.apple.com"
def req(m,p,body=None,raw=None,headers=None,url=None):
    h={"Authorization":"Bearer "+_tok()}
    if body is not None: h["Content-Type"]="application/json"
    if headers: h=headers
    r=urllib.request.Request(url or B+p,method=m,data=raw if raw is not None else (json.dumps(body).encode() if body is not None else None),headers=h)
    try:
        x=urllib.request.urlopen(r,timeout=120).read(); return json.loads(x) if x else {}
    except urllib.error.HTTPError as e: return {"error":e.code,"body":e.read().decode()[:1500]}
def get(p): return req("GET",p)
APP="6827531369"
