# Daftar langkah

Langkah MVP 1–5 di CLAUDE.md sudah selesai. File ini menyimpan langkah lanjutan. Kerjakan dari atas,
satu langkah per sesi (`/clear`), satu branch, satu PR. Centang langkahnya di sini setelah PR-nya
di-merge.

Arah visual baru: **kota isometrik kartun** (seperti Pocket City / SimCity BuildIt).
- Peta diputar 45° (bentuk wajik), bangunan bertingkat dengan atap dan jendela.
- Tokoh tetap slime, dibuat ulang jadi 3D.
- Simulasi tetap di koordinat tanah; hanya gambar dan input yang diproyeksikan (iso 2:1).
- Aset 3D dibuat dari model low-poly di kode Dart, lalu dipanggang jadi sprite 16 arah.

## A. Fondasi isometrik & rasa main
Dikerjakan dulu, berurutan.

- [ ] 1. `feat/iso-fondasi`: proyeksi iso untuk tanah, laut, jalan, dan rute GPS.
      - Kamera iso dengan zoom/skala baru.
      - Joystick dipetakan dari arah layar ke arah tanah (jalan kaki & setir).
      - Urutan kedalaman memakai `x + y` tanah.
      - Peta & minimap tetap utara-atas. Sprite lama dipakai sementara.
- [ ] 2. `feat/model-lowpoly`: renderer model low-poly di Dart.
      - Bentuk dasar: kotak, silinder, bola, ekstrusi.
      - Cahaya searah dan outline tinta.
      - Dipanggang jadi sprite 16 arah lalu di-cache. Ada test render ke PNG.
- [ ] 3. `feat/slime-3d`: slime 3D baru (volume, kilap, mata ekspresif) dengan 16 arah.
      - Animasi kenyal: squash-stretch, toleh halus, debu langkah.
      - Jalan kaki pakai percepatan/perlambatan (tidak meluncur).
- [ ] 4. `feat/motor-3d`: motor 3D baru + rasa berkendara.
      - Motor miring saat belok, gas/rem bertahap, assist lajur ringan.
      - Asap knalpot dan jejak rem.
      - Kamera melihat ke depan sesuai laju. Slime berhelm duduk di motor.
- [ ] 5. `feat/kota-iso`: SPBU, bengkel, rumah, dan ruko jadi model 3D.
      - Blok bangunan kota dibuat prosedural menurut kepadatan jalan.
      - Pohon 3D, lampu jalan, zebra cross.
      - Tanah di-cache per chunk 1×1 km.
- [ ] 6. `docs/readme-iso`: ambil ulang semua screenshot README dari HP.
      - Tambah layar SPBU, bengkel, rumah, dan usaha.

## B. Fitur baru
Urutan boleh digeser.

- [ ] 7. `feat/siang-malam-cuaca`: warna dunia mengikuti jam game.
      - Lampu jalan & lampu motor menyala saat malam.
      - Hujan: jalan licin, order ramai, bayaran naik.
- [ ] 8. `feat/npc-lalu-lintas`: motor, mobil, dan bus NPC mengikuti graf jalan; pejalan kaki di
      trotoar; tabrakan ringan.
- [ ] 9. `feat/lampu-merah-polisi`: lampu merah di simpang besar, polisi, dan tilang.
- [ ] 10. `feat/papan-misi`: Papan Misi untuk memilih pekerjaan per kategori.
      - Kategori: antar dokumen/paket, makanan, penumpang, kurir barang besar, shift pabrik,
        pesanan usaha.
      - Tiap pekerjaan menampilkan bayaran, jarak, tenggat, dan kesulitan.
- [ ] 11. `feat/kerja-pabrik`: shift pabrik Muka Kuning sebagai mini-game singkat, dengan gaji dan
      energi.
- [ ] 12. `feat/dealer-garasi`: bab 3 dengan dealer, beli/ganti motor, garasi, dan cat warna motor.
      Desain: `06-garasi`.
- [ ] 13. `feat/rumah-banyak`: rumah dijual di banyak kelurahan, harga sesuai daerah.
- [ ] 14. `feat/dekorasi-rumah`: ganti lantai, warna dinding, furnitur, dan dekorasi, dengan
      pratinjau sebelum membeli barang.
- [ ] 15. `feat/suara`: musik, suara mesin yang mengikuti kecepatan, klakson, dan suara UI.
- [ ] 16. `feat/menu-utama`: layar menu utama, slot simpanan, pengaturan, dan Credits OSM.
- [ ] 17. `feat/ringkasan-koleksi`: ringkasan harian (desain `08`) dan koleksi/pencapaian
      (desain `18`).

## Catatan
- Rasa setir joystick belum pernah dicoba langsung di HP, karena adb hanya bisa satu sentuhan.
  Dicoba bersama langkah 4.
- Tiap langkah dicek di HP uji (build release lewat adb). Screenshot sebelum/sesudah dilampirkan di
  badan PR.

## Selesai
- [x] Setir motor ikut arah joystick, pemain jadi slime jelly, README dengan screenshot (PR #1).
