import warnings; warnings.filterwarnings('ignore')
import io, contextlib
with contextlib.redirect_stdout(io.StringIO()):
    from load import *
import pickle, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patheffects as pe
from matplotlib.patches import PathPatch
from matplotlib.path import Path
land=pickle.load(open('land.pkl','rb'))
C=dict(sea='#4FB6CC',sea2='#7FCCDA',land='#F4EAD3',forest='#86BF7A',park='#A9D58F',ind='#D6C3E6',com='#F6CFA0',res='#EFE0C0',water='#69C3D6',
       trunk='#E4573D',primary='#F28C38',secondary='#F5C451',tertiary='#FFFFFF',minor='#FFFFFF',edge='#7A5A3A',text='#3B2A1A')
def poly_patch(g,**kw):
    polys=[g] if g.geom_type=='Polygon' else [p for p in getattr(g,'geoms',[]) if p.geom_type=='Polygon']
    for p in polys:
        verts=[];codes=[]
        for ring in [p.exterior,*p.interiors]:
            xy=list(ring.coords); verts+=xy; codes+=[Path.MOVETO]+[Path.LINETO]*(len(xy)-2)+[Path.CLOSEPOLY]
        ax.add_patch(PathPatch(Path(verts,codes),**kw))
def run(out,labels=True,minor=True,dpi_w=4000):
    global ax
    fig=plt.figure(figsize=(W/1000*0.42,H/1000*0.42)); ax=fig.add_axes([0,0,1,1])
    ax.set_xlim(0,W); ax.set_ylim(H,0); ax.set_aspect('equal'); ax.axis('off')
    fig.patch.set_facecolor(C['sea']); ax.set_facecolor(C['sea'])
    poly_patch(land.buffer(180),fc=C['sea2'],ec='none',zorder=1)
    poly_patch(land,fc=C['land'],ec='#C9B48A',lw=1.2,zorder=2)
    for g,r in read('landuse'):
        col={'industrial':C['ind'],'commercial':C['com'],'retail':C['com'],'residential':C['res'],'grass':C['park'],'recreation_groun':C['park']}.get(r['type'])
        if col: poly_patch(g.intersection(land),fc=col,ec='none',zorder=3)
    for g,r in read('natural'):
        col={'forest':C['forest'],'park':C['park'],'water':C['water']}[r['type']] if r['type'] in ('forest','park','water') else None
        if col: poly_patch(g,fc=col,ec='none',zorder=4 if r['type']!='water' else 5)
    sty={'trunk':(5.2,C['trunk'],9),'trunk_link':(3,C['trunk'],9),'primary':(4.2,C['primary'],8),'primary_link':(2.5,C['primary'],8),
         'secondary':(3.2,C['secondary'],7),'secondary_link':(2,C['secondary'],7),'tertiary':(2.3,C['tertiary'],6),'tertiary_link':(1.6,C['tertiary'],6)}
    if minor:
        for t in ('residential','unclassified','living_street'): sty[t]=(0.55,C['minor'],5.5)
    for g,r in read('roads'):
        s=sty.get(r['type'])
        if not s: continue
        lines=[g] if g.geom_type=='LineString' else list(g.geoms)
        for l in lines:
            x,y=l.xy; lw,col,z=s
            ax.plot(x,y,color=C['edge'] if lw>2 else '#D7C7A6',lw=lw+1.4 if lw>2 else lw+0.5,solid_capstyle='round',zorder=z-0.5 if lw>2 else 5.2)
            ax.plot(x,y,color=col,lw=lw,solid_capstyle='round',zorder=z)
    if labels:
        halo=[pe.withStroke(linewidth=3.2,foreground='white')]
        big=[('NAGOYA\nLubuk Baja',103.995,1.142),('BATAM CENTRE\nBatam Kota',104.052,1.128),('BENGKONG',104.032,1.155),('BATU AMPAR',104.005,1.175),
             ('SEKUPANG',103.935,1.120),('BATU AJI',103.990,1.050),('SAGULUNG',103.955,1.040),('MUKA KUNING\nSei Beduk',104.040,1.065),
             ('NONGSA',104.108,1.168),('HANG NADIM\n(Bandara)',104.119,1.121),('TANJUNG PIAYU',104.062,1.012),('TANJUNG UNCANG',103.925,1.055)]
        for t,lo,la in big:
            x,y=P(lo,la); ax.text(x,y,t,ha='center',va='center',fontsize=15,fontweight='bold',color='#5B2C10',path_effects=[pe.withStroke(linewidth=5,foreground='#FFF7E6')],zorder=30,linespacing=0.95)
        bigxy=[P(lo,la) for _,lo,la in big]
        for g,r in read('places'):
            if r['type']=='suburb' and min(((g.x-a)**2+(g.y-b)**2)**.5 for a,b in bigxy)>1500:
                ax.text(g.x,g.y,r['name'],ha='center',va='center',fontsize=7.5,color=C['text'],path_effects=halo,zorder=25,style='italic')
        for g,r in read('points'):
            if r['type']=='fuel':
                ax.scatter([g.x],[g.y],s=46,c='#D62828',edgecolors='white',linewidths=1.2,zorder=26,marker='o')
            elif r['type']=='ferry_terminal' and 0<g.x<W and 0<g.y<H:
                ax.scatter([g.x],[g.y],s=70,c='#1D4E89',edgecolors='white',linewidths=1.3,zorder=26,marker='s')
        x,y=P(103.895,0.986)
        ax.text(x,y,'● SPBU    ■ Pelabuhan ferry    ━ jalan utama (merah > oranye > kuning > putih)\n© OpenStreetMap contributors (ODbL) · data BBBike, 20 Okt 2026',fontsize=9,color='#12333B',va='bottom',zorder=40,
                bbox=dict(fc='white',ec='none',alpha=0.85,boxstyle='round,pad=0.4'))
        x,y=P(104.150,0.986)
        ax.text(x,y,'Ke Jembatan Barelang ↓\n(di luar area data)',fontsize=9,ha='right',va='bottom',color='#12333B',zorder=40,bbox=dict(fc='white',ec='none',alpha=0.85,boxstyle='round,pad=0.4'))
    fig.savefig(out,dpi=dpi_w/fig.get_size_inches()[0],facecolor=C['sea'])
    plt.close(fig)
import sys
run('batam_peta_referensi.png',labels=True)
run('batam_peta_polos.png',labels=False,minor=True)
