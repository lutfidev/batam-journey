from load import *
from shapely.ops import unary_union
from shapely.geometry import Polygon, MultiPolygon, box
import pickle
geoms=[]
for g,r in read('roads'):
    if r['type'] in ('footway','path','steps','corridor','proposed','construction'): continue
    geoms.append(g.buffer(120,resolution=4))
for g,r in read('landuse'): geoms.append(g.buffer(60))
for g,r in read('natural'):
    if r['type']!='water': geoms.append(g.buffer(60))
u=unary_union(geoms).buffer(500,resolution=6).buffer(-560,resolution=6)
def fill(p):
    if p.geom_type=='Polygon': return [Polygon(p.exterior)]
    return [Polygon(q.exterior) for q in p.geoms]
land=unary_union(fill(u)).intersection(box(0,0,W,H))
land=land.simplify(25)
pickle.dump(land,open('land.pkl','wb'))
print(land.geom_type, round(land.area/1e6,1),'km2', W,H)
