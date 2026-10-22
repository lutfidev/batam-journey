import warnings,io,contextlib,json,collections
warnings.filterwarnings('ignore')
with contextlib.redirect_stdout(io.StringIO()):
    from load import *
from shapely.geometry import LineString
MAJOR={'trunk','trunk_link','primary','primary_link','secondary','secondary_link','tertiary','tertiary_link'}
ways=[]
for g,r in read('roads'):
    if r['type'] not in MAJOR: continue
    for l in ([g] if g.geom_type=='LineString' else list(g.geoms)):
        pts=[(round(x,1),round(y,1)) for x,y in l.coords]
        ways.append((pts,r))
cnt=collections.Counter()
for pts,_ in ways:
    for p in set(pts): cnt[p]+=1
    cnt[pts[0]]+=1; cnt[pts[-1]]+=1
nid={};nodes=[];edges=[]
def node(p):
    if p not in nid: nid[p]=len(nodes); nodes.append({'id':len(nodes),'x':p[0],'y':p[1]})
    return nid[p]
for pts,r in ways:
    seg=[pts[0]]
    for p in pts[1:]:
        seg.append(p)
        if cnt[p]>1 or p==pts[-1]:
            ls=LineString(seg)
            simp=[[round(x,1),round(y,1)] for x,y in ls.simplify(4).coords]
            edges.append({'from':node(seg[0]),'to':node(p),'len':round(ls.length,1),'type':r['type'],'name':r['name'] or None,
                          'oneway':r['oneway']==1,'bridge':r['bridge']==1,'pts':simp})
            seg=[p]
pois=[]
for g,r in read('points'):
    if r['type'] in ('fuel','ferry_terminal','hospital','marketplace','hotel','bus_station','monument','attraction','viewpoint','university','cinema') and 0<=g.x<=W and 0<=g.y<=H:
        pois.append({'type':r['type'],'name':r['name'] or None,'x':round(g.x,1),'y':round(g.y,1)})
for g,r in read('places'):
    if r['type'] in ('suburb','city','neighbourhood','quarter'):
        pois.append({'type':'place_'+r['type'],'name':r['name'],'x':round(g.x,1),'y':round(g.y,1)})
out={'meta':{'source':'© OpenStreetMap contributors (ODbL), BBBike extract 2026-10-20',
  'units':'meter; origin = pojok kiri-atas bbox (lon 103.89, lat 1.197); x ke kanan (timur), y ke bawah (selatan)',
  'bbox_lonlat':[103.89,0.98,104.156,1.197],'width_m':round(W),'height_m':round(H),
  'note':'Graf jalan utama (trunk/primary/secondary/tertiary). Node = persimpangan/ujung jalan. Cocok untuk A* di Flame.'},
  'nodes':nodes,'edges':edges,'pois':pois}
json.dump(out,open('batam_road_graph.json','w'),separators=(',',':'),ensure_ascii=False)
print(len(nodes),'nodes',len(edges),'edges',len(pois),'pois', round(sum(e['len'] for e in edges)/1000),'km')
