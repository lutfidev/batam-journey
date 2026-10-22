# Pengolah peta Batam (OpenStreetMap → game)

Script Python untuk membuat ulang `assets/data/batam_road_graph.json` dan gambar referensi peta.
Tidak ikut dibundel ke aplikasi.

## Persiapan
1. Download shapefile dari https://extract.bbbike.org (format "Shapefile (Esri)").
   - Batam saja: kotak 103.89, 0.98 → 104.156, 1.197
   - Termasuk Barelang (Rempang–Galang): kira-kira 103.85, 0.60 → 104.25, 1.20
2. Ekstrak sehingga ada folder `tools/map/shape/` berisi `roads.shp`, `landuse.shp`, `natural.shp`, `places.shp`, `points.shp`, dst.
   (Folder `shape/` sebaiknya masuk `.gitignore`, ukurannya besar.)
3. `pip install pyshp shapely matplotlib`

## Jalankan (dari folder tools/map)
```
python land.py     # bentuk daratan perkiraan -> land.pkl
python render.py   # gambar peta referensi (PNG)
python graph.py    # graf jalan -> batam_road_graph.json
```
Kalau bbox diubah, sesuaikan `LON0, LAT0, LON1, LAT1` di `load.py`, lalu salin hasil JSON ke `assets/data/`.

Catatan: garis pantai hanya perkiraan dari jalan & tata guna lahan. Waduk besar (Duriangkang) tidak ikut di ekspor BBBike.
