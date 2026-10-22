import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import '../ui/palette.dart';
import 'actors/business_station.dart';
import 'actors/fuel_station.dart';
import 'actors/house_station.dart';
import 'actors/motorbike.dart';
import 'actors/player.dart';
import 'actors/workshop_station.dart';
import 'map/road_graph.dart';
import 'map/road_layer.dart';
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
  static const walkZoom = 16.0;
  static const rideZoomMin = 10.5;

  late final RoadGraph graph;
  late final Player player;
  late final Motorbike motor;
  late final Gps gps;
  late final OrderSystem orders;
  late final RoadEventSystem roadEvents;
  late final MissionSystem missions;
  late final ui.Image mapImage;
  final stations = <FuelStation>[];
  final workshops = <WorkshopStation>[];
  final houses = <HouseStation>[];
  final businesses = <BusinessStation>[];
  final controls = Controls();
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
    try {
      await SaveData.load(wallet, tank, orders.ordersDone, stats, parts: _saveParts);
    } catch (_) {
      // Penyimpanan tidak tersedia: mulai dari awal.
    }
    _warnedLow = tank.isLow;
    world.add(RoadLayer(graph));
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
    final kerb = road + normal * (seg.edge.width / 2 + 2.5);

    motor = Motorbike(position: Vector2(kerb.dx, kerb.dy), heading: math.atan2(dir.dy, dir.dx));
    player = Player(position: Vector2(kerb.dx, kerb.dy) + Vector2(dir.dx, dir.dy) * -3.5);
    world.addAll([motor, player]);

    camera.follow(player, snap: true);
    camera.viewfinder.zoom = _baseZoom * walkZoom;
    orders.refreshOffers(playerOffset);
    _refreshHud();
    worldReady.value = true;
  }

  /// SPBU dari POI `fuel`, digeser ke pinggir jalan utama terdekat.
  /// Titik di pinggir jalan utama terdekat dari [poi], di sisi tempat POI berada.
  /// (0,0) bangunan = tepi depan lantai; lantainya memanjang ke atas.
  Offset? _besideRoad(Offset poi) {
    final hit = graph.nearest(poi, maxDist: 400);
    if (hit == null) return null;
    final s = hit.segment;
    final onRoad = s.closestPoint(poi);
    final dir = (s.b - s.a) / s.length;
    var normal = Offset(-dir.dy, dir.dx);
    final away = poi - onRoad;
    if (away.dx * normal.dx + away.dy * normal.dy < 0) normal = -normal;
    final at = onRoad + normal * (s.edge.width / 2 + 1.5);
    return at + Offset(0, 12.0 * math.max(0, normal.dy));
  }

  void _placeStations() {
    for (final poi in graph.pois.where((p) => p.type == 'fuel')) {
      final at = _besideRoad(poi.position);
      if (at == null) continue;
      if (stations.any((st) => (st.position.toOffset() - at).distance < 30)) continue;
      stations.add(
        FuelStation(
          position: Vector2(at.dx, at.dy),
          area: graph.nearestPlaceName(poi.position),
          pumpNo: 1 + stations.length % 4,
        ),
      );
    }
    world.addAll(stations);
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
    final spots = <(Offset, String, Color, String)>[
      if (kos != null) (kos.position, Housing.kosId, BColors.oranye, 'Kos Bu Ros'),
      for (final l in houseListings)
        if (graph.findPoi((p) => p.name == l.poiName) case final poi?) (poi.position, l.id, l.roof, l.name),
    ];
    for (final (pos, id, roof, title) in spots) {
      final base = _besideRoad(pos);
      if (base == null) continue;
      // Geser sepanjang jalan bila sudah ada SPBU/bengkel/rumah di situ (mis. kos & Bengkel Mas Joko).
      final at =
          [
            for (final dx in const [0.0, 22.0, -22.0, 44.0, -44.0]) base + Offset(dx, 0),
          ].firstWhere(
            (c) => !_occupied(c) && (c == base || graph.clearance(c + const Offset(0, -6), maxDist: 12) > 0.5),
            orElse: () => base,
          );
      houses.add(HouseStation(position: Vector2(at.dx, at.dy), homeId: id, roof: roof, title: title));
    }
    world.addAll(houses);
  }

  bool _occupied(Offset at) =>
      [...stations, ...workshops, ...houses, ...businesses].any((b) => (b.position.toOffset() - at).distance < 20);

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
      final base = poi == null ? null : _besideRoad(poi.position);
      if (base == null) continue;
      final at =
          [
            for (final dx in const [0.0, 22.0, -22.0, 44.0, -44.0]) base + Offset(dx, 0),
          ].firstWhere(
            (c) => !_occupied(c) && (c == base || graph.clearance(c + const Offset(0, -6), maxDist: 12) > 0.5),
            orElse: () => base,
          );
      businesses.add(BusinessStation(position: Vector2(at.dx, at.dy), type: t));
    }
    world.addAll(businesses);
  }

  /// Pin usaha untuk peta.
  List<Poi> get businessPois => [for (final b in businesses) Poi('business', b.type.name, b.position.toOffset())];

  void openBusiness(String? id) {
    screenTarget = id;
    open(GameScreen.business);
  }

  Poi _bizPoi(String id) {
    final st = businesses.firstWhere((b) => b.type.id == id);
    return Poi('business', st.type.name, st.position.toOffset() + const Offset(0, 2));
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
    final spots = <(Offset, String)>[];
    for (final poi in graph.pois) {
      if (poi.type != 'marketplace' || !(poi.name ?? '').toLowerCase().contains('motor')) continue;
      final at = _besideRoad(poi.position);
      if (at != null) spots.add((at, 'Bengkel Mas Joko'));
    }
    for (final st in stations) {
      for (final dx in const [22.0, -22.0]) {
        final at = st.position.toOffset() + Offset(dx, 0);
        if (graph.clearance(at + const Offset(0, -6), maxDist: 12) > 0.5) {
          spots.add((at, 'Bengkel ${st.area}'));
          break;
        }
      }
    }
    for (final (at, name) in spots) {
      if (workshops.any((w) => (w.position.toOffset() - at).distance < 25)) continue;
      if (stations.any((st) => (st.position.toOffset() - at).distance < 18)) continue;
      workshops.add(WorkshopStation(position: Vector2(at.dx, at.dy), name: name));
    }
    world.addAll(workshops);
  }

  double get _baseZoom => size.y / 390;

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
      position: s.position.toOffset() + const Offset(0, -6),
    );
  }

  void closeMap() => closeScreen();

  /// Boleh isi bensin: dekat SPBU dan (kalau naik motor) sudah berhenti.
  bool get canRefuel => nearStation.value != null && motor.speedKmh <= 5;

  /// Apakah lingkaran ([p], [r]) menimpa lantai SPBU atau bengkel (untuk pohon).
  bool isNearBuilding(Offset p, double r) {
    bool hit(Offset front, double halfW, double depth) =>
        p.dx + r > front.dx - halfW &&
        p.dx - r < front.dx + halfW &&
        p.dy + r > front.dy - depth &&
        p.dy - r < front.dy + 1;
    return stations.any((s) => hit(s.position.toOffset(), 9.5, 15)) ||
        workshops.any((w) => hit(w.position.toOffset(), 8.5, 15)) ||
        houses.any((h) => hit(h.position.toOffset(), 8.5, 15)) ||
        businesses.any((b) => hit(b.position.toOffset(), 8.5, 15));
  }

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
      if ((s.position.toOffset() + const Offset(0, -6) - p).distance <= FuelStation.serviceRange) near = s;
    }
    nearStation.value = near;

    WorkshopStation? nearW;
    for (final w in workshops) {
      if ((w.position.toOffset() + const Offset(0, -5) - p).distance <= WorkshopStation.serviceRange) nearW = w;
    }
    nearWorkshop.value = nearW;

    BusinessStation? nearB;
    for (final b in businesses) {
      if ((b.position.toOffset() + const Offset(0, -5) - p).distance <= BusinessStation.serviceRange) nearB = b;
    }
    nearBusiness.value = nearB;

    HouseStation? nearH;
    for (final h in houses) {
      if ((h.position.toOffset() + const Offset(0, -5) - p).distance <= HouseStation.serviceRange) nearH = h;
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
