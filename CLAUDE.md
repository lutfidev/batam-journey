# Batam: The Journey Begins — konteks untuk Claude Code

Game mobile open-world (Flutter + Flame) berlatar seluruh Pulau Batam. Pemain adalah perantau
yang kerja ojek/pabrik, menabung, beli rumah, modifikasi kendaraan, dan membangun usaha.
Orientasi layar: **landscape**. Ukuran desain acuan: 844×390.

## Referensi desain
- Semua layar ada di `docs/design/` (PNG/PDF hasil export dari canvas Claude Design).
  Nama file mengikuti nomor layar, mis. `01-gameplay-menyetir.png`, `15-jalan-kaki.png`.
- Ikuti warna, huruf, bentuk tombol, dan tata letak HUD dari gambar-gambar itu.
- Peta referensi: `docs/reference/batam_peta_referensi.png` (berlabel) dan `batam_peta_polos.png`.

## Gaya visual (wajib konsisten)
- Kamera **mengikuti karakter dari dekat** (bukan peta luas). Sudut pandang 3/4 top-down:
  bangunan tampak fasad depan + atap, kendaraan yang bergerak horizontal tampak samping.
- Karakter & kendaraan terlihat "3D": bayangan di bawah, gradasi shading, outline gelap tipis.
  Rencana aset: model 3D sederhana (Blender) yang di-render jadi sprite sheet 8 arah,
  atau sprite 2D berbayang yang dibuat sesuai gambar desain.
- Font: **Baloo 2** (judul, angka uang, tombol besar) dan **Nunito** (teks UI) — pakai paket `google_fonts`.
- Tombol: border 3px `#2B1D12`, radius 14–18, bayangan padat 4px ke bawah (tanpa blur).

### Warna
| Token | Hex |
|---|---|
| ink (teks/border) | #2B1D12 |
| cream (panel) | #FFF6E5 |
| tanah | #F4EAD3 |
| aspal | #4A5566 |
| laut | #4FB6CC |
| hutan | #86BF7A |
| atap merah | #E4573D |
| oranye | #F28C38 |
| kuning | #F5C451 |
| hijau aksi (GAS, beli) | #3E9B5B |
| biru pemain | #1D4E89 |
| industri | #D6C3E6 |

## Data peta
- `assets/data/batam_road_graph.json` — graf jalan utama Batam dari OpenStreetMap.
  - Satuan **meter**; origin = pojok kiri-atas bbox (lon 103.89, lat 1.197); x → timur, y → selatan.
  - Ukuran dunia asli ±29,6 × 24,0 km. **Skala game: kalikan koordinat 0,2** (bisa disetel lewat satu konstanta `worldScale`).
  - `nodes`: `{id, x, y}` = persimpangan/ujung jalan.
  - `edges`: `{from, to, len, type, name, oneway, bridge, pts}` — `pts` = polyline untuk digambar/diikuti NPC.
    `type`: trunk > primary > secondary > tertiary (+ `_link`).
  - `pois`: `{type, name, x, y}` — `fuel` (SPBU), `ferry_terminal`, `hospital`, `marketplace`, `place_suburb` (nama kelurahan), dll.
  - Barelang belum termasuk (data berhenti di Tembesi). Generate ulang dengan `tools/map/` jika perlu.
- Lisensi: © OpenStreetMap contributors (ODbL) — wajib tampil di layar Credits.

## Arsitektur yang diinginkan
- `lib/game/` — `BatamGame extends FlameGame`, world, camera follow karakter, chunk loader.
- `lib/game/map/` — loader JSON, road graph, A* (GPS & rute NPC), chunk 1×1 km.
- `lib/game/actors/` — Player (mode jalan kaki & berkendara), Vehicle, NPC traffic, Pedestrian.
- `lib/game/systems/` — waktu & cuaca, ekonomi (uang, bensin), kejadian jalan, misi.
- `lib/ui/` — overlay Flutter untuk HUD, HP, peta, SPBU, properti, garasi, bengkel, usaha.
- State: Riverpod atau Provider; simpan progres lokal (shared_preferences / hive).

## Urutan pengerjaan (MVP dulu)
1. Load graf → gambar jalan debug, kamera ikut karakter, zoom dekat.
2. Karakter jalan kaki (joystick) + naik/turun motor + motor bisa dikendarai.
3. Minimap + peta penuh + GPS A*.
4. Bensin & SPBU (POI `fuel`), uang, order ojek pertama.
5. Kejadian di jalan → misi bab 1–2 → bengkel → rumah → usaha.
