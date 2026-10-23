import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:path_provider/path_provider.dart';

import '../ui/palette.dart';
import 'actors/business_station.dart';
import 'actors/destination_pin.dart';
import 'actors/fuel_station.dart';
import 'actors/house_station.dart';
import 'actors/motorbike.dart';
import 'actors/player.dart';
import 'actors/skid_marks.dart';
import 'actors/workshop_station.dart';
import 'city/city_gen.dart';
import 'city/city_layer.dart';
import 'iso.dart';
import 'map/land_mask.dart';
import 'map/road_graph.dart';
import 'map/road_layer.dart';
import 'model3d/models/buildings.dart';
import 'sprites/sprite_library.dart';
import 'systems/business.dart';
import 'systems/clock.dart';
import 'systems/economy.dart';
import 'systems/gps.dart';
import 'systems/housing.dart';
import 'systems/missions.dart';
import 'systems/needs.dart';
import 'systems/orders.dart';
import 'systems/road_events.dart';
import 'systems/story.dart';
import 'systems/workshop.dart';

/// Input gabungan dari HUD sentuh dan keyboard (untuk uji di desktop).
class Controls {
  final Vector2 stick = Vector2.zero();
  bool gasBtn = false, brakeBtn = false;

  final Set<LogicalKeyboardKey> _keys = {};

  bool _k(LogicalKeyboardKey a, LogicalKeyboardKey b) => _keys.contains(a) || _keys.contains(b);

  Vector2 get move {
    final v = stick.clone();
    if (_k(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA)) v.x -= 1;
    if (_k(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD)) v.x += 1;
    if (_k(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW)) v.y -= 1;
    if (_k(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS)) v.y += 1;
    return v;
  }

  /// Saat berkendara, [move] menjadi arah setir; gas & rem pakai tombol tersendiri.
  bool get gas => gasBtn || _k(LogicalKeyboardKey.space, LogicalKeyboardKey.keyJ);
  bool get brake => brakeBtn || _k(LogicalKeyboardKey.keyX, LogicalKeyboardKey.keyK);

  void releaseAll() {
    stick.setZero();
    gasBtn = brakeBtn = false;
  }
}

/// Notifier yang berdenyut tiap frame (untuk minimap).
class FrameTick extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Layar overlay penuh di atas game.
enum GameScreen { none, map, fuel, phone, missions, story, workshop, property, home, business }

class BatamGame extends FlameGame with KeyboardEvents {
  BatamGame() : super();

  /// Zoom acuan pada tinggi layar desain 390 px.
  static const walkZoom = 13.0;
  static const rideZoomMin = 8.5;

  late final RoadGraph graph;
  late final Player player;
  late final Motorbike motor;
  late final Gps gps;
  late final OrderSystem orders;
  late final RoadEventSystem roadEvents;
  late final MissionSystem missions;
  late final ui.Image mapImage;

  /// Mask darat/laut dari [mapImage].
  late final LandMask mask;

  /// Lapisan kota 3D (bangunan, pohon, lampu) yang juga menggambar aktor.
  late final CityLayer city;
  late final sprites = SpriteLibrary(
    loadImage: images.load,
    loadText: (f) => assets.readFile('images/$f'),
    cacheDir: () async => kIsWeb ? null : '${(await getApplicationCacheDirectory()).path}/sprites',
  );
  final stations = <FuelStation>[];
  final workshops = <WorkshopStation>[];
  final houses = <HouseStation>[];
  final businesses = <BusinessStation>[];
  final controls = Controls();
  final skids = SkidMarks();
  final wallet = Wallet();
  final tank = FuelTank();
  final stats = PlayerStats();
  final workshop = Workshop();
  final clock = GameClock();
  final needs = Needs();
  late final housing = Housing(wallet: wallet, toast: toast);
  late final business = BusinessSystem(wallet: wallet, stats: stats, toast: toast);

  /// Id rumah untuk layar [GameScreen.home] / [GameScreen.property].
  String? screenTarget;

  /// Flag selesai load. Jangan pakai `loaded`/`isLoaded` (bentrok dengan Flame).
  final worldReady = ValueNotifier(false);

  // State HUD — ValueNotifier hanya memberi tahu saat nilainya berubah.
  final mode = ValueNotifier(PlayerMode.walking);
  final speedKmh = ValueNotifier(0);
  final areaName = ValueNotifier('');
  final roadName = ValueNotifier<String?>(null);
  final motorDistanceM = ValueNotifier(0);
  final nearStation = ValueNotifier<FuelStation?>(null);
  final nearWorkshop = ValueNotifier<WorkshopStation?>(null);
  final nearHouse = ValueNotifier<HouseStation?>(null);
  final nearBusiness = ValueNotifier<BusinessStation?>(null);
  final screen = ValueNotifier(GameScreen.none);
  final toast = ValueNotifier<String?>(null);

  /// Kartu kejadian/dialog yang sedang tampil (layar [GameScreen.story]).
  final story = ValueNotifier<StoryEvent?>(null);
  final frame = FrameTick();

  ValueNotifier<int> get money => wallet.money;

  double _hudTimer = 0;
  final _lastMotorPos = Vector2.zero();
  double _rideDist = 0, _brakeDist = 0;
  final _warnedParts = <MotorPart>{};
  bool _warnedSleepy = false, _warnedHungry = false;
  double _saveTimer = 10;
  bool _warnedLow = false, _warnedEmpty = false;

  @override
  Color backgroundColor() => BColors.laut;

  @override
  Future<void> onLoad() async {
    graph = await RoadGraph.load();
    gps = Gps(graph, toast: toast);
    orders = OrderSystem(graph: graph, gps: gps, wallet: wallet, toast: toast)..onProgress = save;
    gps.onArrive = orders.handleArrive;
    roadEvents = RoadEventSystem(
      wallet: wallet,
      stats: stats,
      orders: orders,
      restrictMotor: (cap, s) => motor.restrict(cap, s),
      roadName: () => roadName.value ?? '',
      areaName: () => areaName.value,
      ferryName: _nearestFerryName,
      workshop: workshop,
    );
    missions = MissionSystem(graph: graph, wallet: wallet, stats: stats, orders: orders, gps: gps, toast: toast)
      ..onProgress = save;
    orders.onCompleted = (o) {
      missions.onOrderCompleted(o);
      final id = o.storyId;
      if (id != null && id.startsWith('shop:')) {
        final bizId = id.substring(5);
        business.deliverShopping(bizId);
        toast.value = 'Belanjaan sampai, stok ${business.type(bizId).name} penuh lagi!';
      }
    };
    missions.onCompleted = (m) {
      if (m.id == 'c1_kos') housing.rentKos(clock.day.value);
      if (m.id == 'c2_kos') housing.extendKos();
    };
    clock.onNewDay = (day) {
      housing.onNewDay(day);
      business.onNewDay();
      save();
    };
    mapImage = await images.load('batam_peta.jpg');
    mask = await LandMask.fromImage(mapImage, graph.size);
    try {
      await SaveData.load(wallet, tank, orders.ordersDone, stats, parts: _saveParts);
    } catch (_) {
      // Penyimpanan tidak tersedia: mulai dari awal.
    }
    _warnedLow = tank.isLow;
    city = CityLayer(graph: graph, mask: mask);
    world.addAll([RoadLayer(graph, mask), skids, city]);
    _placeStations();
    _placeWorkshops();
    _placeHouses();
    _placeBusinesses();
    // Simpanan lama: kos sudah disewa lewat misi sebelum sistem rumah ada.
    if (stats.missionsDone.value.contains('c1_kos') && !housing.kosRented.value && housing.kosPaidUntil == 0) {
      housing.rentKos(clock.day.value);
    }
    tank.modFactor = () => workshop.fuelFactor;
    orders.payBonus = (tab) =>
        (tab == OrderTab.orang ? 1 : workshop.cargoPayFactor) * workshop.tipFactor * needs.tipFactor;

    // Mulai di sekitar Nagoya (Lubuk Baja), di trotoar dekat jalan.
    final anchor =
        graph.findPoi((p) => p.name == '21 Cinema Nagoya Hill')?.position ??
        Offset(graph.size.width / 2, graph.size.height / 2);
    final hit = graph.nearest(anchor, maxDist: 200)!;
    final seg = hit.segment;
    final road = seg.closestPoint(anchor);
    final dir = (seg.b - seg.a) / seg.length;
    final normal = Offset(-dir.dy, dir.dx);
    final kerb = road + normal * (seg.edge.width / 2 + 1.2);

    final (slime, bike, pin) = await (
      sprites.load(SpriteIds.slime),
      sprites.load(SpriteIds.motor),
      sprites.load(SpriteIds.pinTujuan),
    ).wait;
    motor = Motorbike(position: Vector2(kerb.dx, kerb.dy), sprite: bike, heading: math.atan2(dir.dy, dir.dx));
    player = Player(position: Vector2(kerb.dx, kerb.dy) + Vector2(dir.dx, dir.dy) * -3.5, sprite: slime);
    city.addAll([motor, player, DestinationPin(pin)]);

    _followPlayer();
    camera.viewfinder.zoom = _baseZoom * walkZoom;
    orders.refreshOffers(playerOffset);
    _refreshHud();
    worldReady.value = true;
    unawaited(_buildCity());
  }

  /// Blok kota dibuat di isolate lain (tidak menahan layar), lalu sprite kota
  /// dipanggang satu per satu; tiap jenis muncul begitu sprite-nya siap.
  Future<void> _buildCity() async {
    final g = graph, m = mask;
    final reserved = [
      for (final b in [...stations.map((s) => s.site), ...workshops.map((w) => w.site)]) b.footprint,
      for (final h in houses) h.site.footprint,
      for (final b in businesses) b.site.footprint,
    ];
    final specs = kIsWeb ? generateBuildings(g, m, reserved) : await Isolate.run(() => generateBuildings(g, m, reserved));
    city.addBuildings(specs);
    for (final id in SpriteIds.city) {
      await sprites.load(id);
    }
  }

  /// Tapak bangunan penting yang sudah dipakai (SPBU, bengkel, rumah, ruko usaha).
  final _taken = RectIndex();

  /// Lokasi bangunan [info] di pinggir jalan terdekat dari [near], menghadap jalan,
  /// bergeser sepanjang jalan bila tempatnya sudah terpakai.
  Site? _site(Offset near, BuildingInfo info) {
    final site = siteBeside(graph, near, info, taken: _taken, mask: mask);
    if (site != null) _taken.add(site.footprint);
    return site;
  }

  /// SPBU dari POI `fuel`, di pinggir jalan utama terdekat.
  void _placeStations() {
    for (final poi in graph.pois.where((p) => p.type == 'fuel')) {
      if (stations.any((st) => (st.site.center - poi.position).distance < 30)) continue;
      final site = _site(poi.position, spbuInfo);
      if (site == null) continue;
      stations.add(FuelStation(site: site, area: graph.nearestPlaceName(poi.position), pumpNo: 1 + stations.length % 4));
    }
    for (final s in stations) {
      city.addProps(s.props);
    }
  }

  Map<String, JsonState> get _saveParts => {
    'workshop': workshop,
    'clock': clock,
    'needs': needs,
    'housing': housing,
    'business': business,
  };

  /// Kos Bu Ros (lokasi misi) dan rumah-rumah dijual dari desain Property.
  void _placeHouses() {
    final kos = missions.missions.firstWhere((m) => m.id == 'c1_kos').place;
    final spots = <(Offset, String, String)>[
      if (kos != null) (kos.position, Housing.kosId, 'Kos Bu Ros'),
      for (final l in houseListings)
        if (graph.findPoi((p) => p.name == l.poiName) case final poi?) (poi.position, l.id, l.name),
    ];
    for (final (pos, id, title) in spots) {
      final site = _site(pos, HouseStation.modelFor(id).$3);
      if (site == null) continue;
      houses.add(HouseStation(site: site, homeId: id, title: title));
    }
    for (final h in houses) {
      city.addProps(h.props(housing));
    }
  }

  /// Pin rumah untuk peta: rumah dijual dan tempat tinggalmu.
  List<Poi> get housePois => [
    for (final h in houses)
      if (housing.isHome(h.homeId))
        Poi('home', h.isKos ? 'Kos Bu Ros' : h.title, h.position.toOffset())
      else if (!h.isKos)
        Poi('house_sale', h.title, h.position.toOffset()),
  ];

  void openHome(String id) {
    screenTarget = id;
    open(GameScreen.home);
  }

  void openProperty(String? id) {
    screenTarget = id;
    open(GameScreen.property);
  }

  /// Ruko usaha di lokasi desain Business (Batam Centre, Muka Kuning, Bengkong, Nagoya).
  void _placeBusinesses() {
    for (final t in bizTypes) {
      final poi = graph.findPoi((p) => p.name == t.poiName);
      final site = poi == null ? null : _site(poi.position, rukoInfo);
      if (site == null) continue;
      businesses.add(BusinessStation(site: site, type: t));
    }
    for (final b in businesses) {
      city.addProps(b.props(business));
    }
  }

  /// Pin usaha untuk peta.
  List<Poi> get businessPois => [for (final b in businesses) Poi('business', b.type.name, b.position.toOffset())];

  void openBusiness(String? id) {
    screenTarget = id;
    open(GameScreen.business);
  }

  Poi _bizPoi(String id) {
    final st = businesses.firstWhere((b) => b.type.id == id);
    return Poi('business', st.type.name, st.position.toOffset());
  }

  /// Belanja bahan sendiri: bayar di muka, jemput di pasar terdekat, antar ke usaha.
  bool startShopping(String id) {
    if (orders.hasActive) return false;
    final shop = _bizPoi(id);
    final markets = graph.pois.where((p) => p.type == 'marketplace' && (p.name ?? '').startsWith('Pasar')).toList()
      ..sort(
        (a, b) => (a.position - shop.position).distanceSquared.compareTo((b.position - shop.position).distanceSquared),
      );
    if (markets.isEmpty) return false;
    final price = business.selfShopPrice(id);
    final order = orders.makeStory(
      storyId: 'shop:$id',
      kind: 'BELANJA',
      tab: OrderTab.antar,
      pickup: markets.first,
      pickupTitle: markets.first.name!,
      dropoff: shop,
      dropoffTitle: shop.name!,
      pay: 0,
    );
    if (order == null || !business.paySelfShop(id)) return false;
    if (!orders.take(order, playerOffset)) {
      wallet.earn(price);
      return false;
    }
    save();
    return true;
  }

  /// Terima pesanan besar: jemput di usaha, antar ke tujuan, dibayar penuh.
  bool startBigOrder(String id) {
    if (orders.hasActive) return false;
    final big = business.get(id)?.bigOrder;
    final target = big == null ? null : graph.findPoi((p) => p.name == big.targetPoi);
    if (big == null || target == null) return false;
    final shop = _bizPoi(id);
    final order = orders.makeStory(
      storyId: 'catering:$id',
      kind: 'KATERING',
      tab: OrderTab.antar,
      pickup: shop,
      pickupTitle: shop.name!,
      dropoff: target,
      dropoffTitle: target.name!,
      pay: big.pay,
    );
    if (order == null || business.acceptBigOrder(id) == null) return false;
    orders.take(order, playerOffset);
    save();
    return true;
  }

  /// Bengkel: toko motor di data peta ("Bengkel Mas Joko") + satu di samping tiap SPBU.
  void _placeWorkshops() {
    final spots = <(Offset, String)>[
      for (final poi in graph.pois)
        if (poi.type == 'marketplace' && (poi.name ?? '').toLowerCase().contains('motor')) (poi.position, 'Bengkel Mas Joko'),
      for (final st in stations) (st.site.center, 'Bengkel ${st.area}'),
    ];
    for (final (near, name) in spots) {
      if (workshops.any((w) => (w.site.center - near).distance < 25)) continue;
      final site = _site(near, bengkelInfo);
      if (site == null) continue;
      workshops.add(WorkshopStation(site: site, name: name));
    }
    for (final w in workshops) {
      city.addProps(w.props);
    }
  }

  double get _baseZoom => size.y / 390;

  /// Pandangan kamera ke depan motor (unit tanah), dihaluskan.
  final _look = Vector2.zero();

  /// Kamera menempel ke titik layar iso pemain (posisi pemain = koordinat tanah),
  /// digeser ke depan sesuai laju saat berkendara.
  void _followPlayer() => camera.viewfinder.position = isoOfV(player.position + _look);

  void clampToWorld(Vector2 p) {
    p.x = p.x.clamp(0, graph.size.width);
    p.y = p.y.clamp(0, graph.size.height);
  }

  /// Posisi pemain di dunia (untuk UI peta).
  Offset get playerOffset => player.position.toOffset();

  /// Arah hadap pemain/motor dalam radian (0 = timur), untuk panah peta.
  double get heading => player.isRiding ? motor.heading : player.heading;

  /// Buka layar overlay. Peta & SPBU menjeda game; HP tidak (desain: game tetap jalan).
  void open(GameScreen s) {
    controls.releaseAll();
    if (s != GameScreen.phone) pauseEngine();
    screen.value = s;
  }

  void closeScreen() {
    screen.value = GameScreen.none;
    resumeEngine();
    _refreshHud();
  }

  void openMap() => open(GameScreen.map);

  /// Tampilkan kartu kejadian/dialog (menjeda game).
  void showStory(StoryEvent e) {
    if (screen.value != GameScreen.none) return;
    story.value = e;
    open(GameScreen.story);
  }

  void closeStory() {
    story.value = null;
    closeScreen();
  }

  String _nearestFerryName() {
    final p = playerOffset;
    final ferries = graph.pois.where((x) => x.type == 'ferry_terminal' && x.name != null).toList()
      ..sort((a, b) => (a.position - p).distanceSquared.compareTo((b.position - p).distanceSquared));
    return ferries.isEmpty ? 'Batam Centre' : ferries.first.name!;
  }

  /// SPBU terdekat sebagai tujuan GPS (misi isi bensin).
  Destination? nearestStationDestination() {
    if (stations.isEmpty) return null;
    final p = playerOffset;
    final s = stations.reduce(
      (a, b) => (a.position.toOffset() - p).distanceSquared < (b.position.toOffset() - p).distanceSquared ? a : b,
    );
    return Destination(
      title: 'SPBU BensinKu ${s.area}',
      subtitle: s.area,
      position: s.position.toOffset(),
    );
  }

  void closeMap() => closeScreen();

  /// Boleh isi bensin: dekat SPBU dan (kalau naik motor) sudah berhenti.
  bool get canRefuel => nearStation.value != null && motor.speedKmh <= 5;

  /// Boleh masuk bengkel: dekat bengkel dan (kalau naik motor) sudah berhenti.
  bool get canEnterWorkshop => nearWorkshop.value != null && motor.speedKmh <= 5;

  /// Bayar & isi bensin. Mengembalikan false bila uang kurang.
  bool buyFuel(double liters, FuelGrade grade) {
    final add = liters.clamp(0.0, tank.space);
    if (add <= 0 || !wallet.pay(FuelTank.price(add, grade))) return false;
    tank.fill(add, grade);
    stats.fuelPurchases.value++;
    _warnedLow = tank.isLow;
    _warnedEmpty = false;
    save();
    return true;
  }

  void save() {
    _saveTimer = 10;
    SaveData.save(wallet, tank, orders.ordersDone.value, stats, parts: _saveParts).catchError((_) {});
  }

  bool get canBoard => !player.isRiding && player.position.distanceTo(motor.position) <= Player.boardRange;

  /// Naik motor (bila dekat) atau turun (bila hampir berhenti).
  void toggleRide() {
    if (player.isRiding) {
      if (motor.speedKmh > 5) return;
      motor.speed = 0;
      player.dismount();
    } else if (canBoard) {
      player.board(motor);
    } else {
      return;
    }
    controls.releaseAll();
    mode.value = player.mode;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!worldReady.value) return;

    final speedFrac = (motor.speed.abs() / Motorbike.maxSpeed).clamp(0.0, 1.0);
    final targetZoom = _baseZoom * (player.isRiding ? walkZoom - (walkZoom - rideZoomMin) * speedFrac : walkZoom);
    final vf = camera.viewfinder;
    vf.zoom += (targetZoom - vf.zoom) * math.min(1, dt * 2.5);
    final ahead = player.isRiding ? lookAheadOf(motor.heading, motor.speed) : Vector2.zero();
    _look.add((ahead - _look)..scale(math.min(1, dt * 1.8)));
    _followPlayer();

    speedKmh.value = motor.speedKmh.round();
    frame.tick();
    clock.update(dt);
    needs.tick(dt * GameClock.speed / 60, riding: player.isRiding);
    if (screen.value == GameScreen.none) {
      final e = roadEvents.update(dt, riding: player.isRiding, speedKmh: motor.speedKmh);
      if (e != null) showStory(e);
    }
    // Jarak tempuh motor untuk keausan (dihitung berkala di _refreshHud).
    final moved = motor.position.distanceTo(_lastMotorPos);
    _lastMotorPos.setFrom(motor.position);
    if (player.isRiding) {
      if (controls.brake) {
        _brakeDist += moved;
      } else {
        _rideDist += moved;
      }
    }
    _hudTimer -= dt;
    if (_hudTimer <= 0) _refreshHud();
    _saveTimer -= dt;
    if (_saveTimer <= 0) save();
  }

  void _refreshHud() {
    const dt = 0.3;
    _hudTimer = dt;
    final p = playerOffset;
    gps.update(p, dt);
    orders.update(dt, p);
    areaName.value = graph.nearestPlaceName(p);
    final hit = graph.nearest(p, maxDist: 12);
    roadName.value = hit?.segment.edge.name;
    motorDistanceM.value = (player.position.distanceTo(motor.position) / worldScale).round();

    FuelStation? near;
    for (final s in stations) {
      if ((s.position.toOffset() - p).distance <= FuelStation.serviceRange) near = s;
    }
    nearStation.value = near;

    WorkshopStation? nearW;
    for (final w in workshops) {
      if ((w.position.toOffset() - p).distance <= WorkshopStation.serviceRange) nearW = w;
    }
    nearWorkshop.value = nearW;

    BusinessStation? nearB;
    for (final b in businesses) {
      if ((b.position.toOffset() - p).distance <= BusinessStation.serviceRange) nearB = b;
    }
    nearBusiness.value = nearB;

    HouseStation? nearH;
    for (final h in houses) {
      if ((h.position.toOffset() - p).distance <= HouseStation.serviceRange) nearH = h;
    }
    nearHouse.value = nearH;

    if (needs.sleepy && !_warnedSleepy) {
      _warnedSleepy = true;
      toast.value = 'Ngantuk! Motor jadi pelan, pulang tidur dulu';
    } else if (!needs.sleepy) {
      _warnedSleepy = false;
    }
    if (needs.starving && !_warnedHungry) {
      _warnedHungry = true;
      if (toast.value == null) toast.value = 'Perut keroncongan, masak di rumah atau mampir warung';
    } else if (!needs.starving) {
      _warnedHungry = false;
    }

    if (_rideDist + _brakeDist > 0) {
      workshop.wear(_rideDist);
      workshop.wear(_brakeDist, braking: true);
      _rideDist = _brakeDist = 0;
      for (final part in MotorPart.values) {
        final bad = workshop.level(part) < Workshop.badLevel;
        if (!bad) {
          _warnedParts.remove(part);
        } else if (_warnedParts.add(part) && toast.value == null) {
          toast.value = '${part.label} motor sudah aus, mampir ke bengkel';
        }
      }
    }

    // Hanya saat tidak ada layar lain, supaya dialog tiba-di-lokasi tidak terlewat.
    if (screen.value == GameScreen.none) {
      final dialog = missions.update(p, riding: player.isRiding);
      if (dialog != null) showStory(dialog);
    }

    if (tank.isEmpty && !_warnedEmpty) {
      _warnedEmpty = true;
      toast.value = 'Bensin habis! Dorong motor ke SPBU terdekat';
    } else if (tank.isLow && !_warnedLow) {
      _warnedLow = true;
      toast.value = 'Bensin tinggal sedikit, cari SPBU';
    }
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    controls._keys
      ..clear()
      ..addAll(keysPressed);
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.keyE || event.logicalKey == LogicalKeyboardKey.keyF)) {
      toggleRide();
    }
    return KeyEventResult.handled;
  }
}
