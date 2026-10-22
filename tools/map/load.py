import shapefile, math
from shapely.geometry import shape, LineString, Point
LON0,LAT0,LON1,LAT1=103.89,0.98,104.156,1.197
KX=111320*math.cos(math.radians(1.09)); KY=110574
def P(lon,lat): return ((lon-LON0)*KX,(LAT1-lat)*KY)   # meters, y down
W,H=P(LON1,LAT0)
def proj(geom):
    from shapely.ops import transform
    return transform(lambda x,y,z=None:P(x,y),geom)
def read(name):
    r=shapefile.Reader('shape/'+name)
    for s,rec in zip(r.iterShapes(),r.iterRecords()):
        if not s.points: continue
        try: g=proj(shape(s.__geo_interface__))
        except Exception: continue
        yield g,rec.as_dict()
