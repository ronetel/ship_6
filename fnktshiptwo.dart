import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:isolate';

const BOARD_SIZE = 10;
const SHIP_SIZES = [4, 3, 3, 2, 2, 2, 1, 1, 1, 1];
const ROWS = 'ABCDEFGHIJ'; // Английские буквы

final StreamController<String> gameLogStream =
    StreamController<String>.broadcast();

class GameStats {
  String playerName;
  int hits = 0;
  int misses = 0;
  int shipsDestroyed = 0;
  int shipsLost = 0;
  int shipsRemaining = 10;
  int totalShots = 0;
  DateTime? gameStart;
  DateTime? gameEnd;

  GameStats(this.playerName);

  double get accuracy => totalShots > 0 ? (hits / totalShots * 100) : 0;
  Duration get gameDuration => gameEnd != null && gameStart != null
      ? gameEnd!.difference(gameStart!)
      : Duration.zero;

  void startGame() => gameStart = DateTime.now();
  void endGame() => gameEnd = DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'playerName': playerName,
      'hits': hits,
      'misses': misses,
      'shipsDestroyed': shipsDestroyed,
      'shipsLost': shipsLost,
      'shipsRemaining': shipsRemaining,
      'totalShots': totalShots,
      'accuracy': accuracy.toStringAsFixed(2),
      'gameDuration':
          '${gameDuration.inMinutes} мин ${gameDuration.inSeconds % 60} сек',
      'gameDate': gameStart?.toIso8601String() ?? '',
    };
  }

  @override
  String toString() {
    return '''
Игрок: $playerName
Попадания: $hits
Промахи: $misses
Уничтожено кораблей противника: $shipsDestroyed
Потеряно кораблей: $shipsLost
Осталось кораблей: $shipsRemaining
Всего выстрелов: $totalShots
Точность: ${accuracy.toStringAsFixed(2)}%
Длительность игры: ${gameDuration.inMinutes} мин ${gameDuration.inSeconds % 60} сек
''';
  }
}

class Board {
  List<List<String>> grid;
  List<List<List<int>>> ships = [];
  int hits = 0;
  int shipsSunk = 0;

  Board()
    : grid = List.generate(BOARD_SIZE, (i) => List.filled(BOARD_SIZE, '.'));

  bool isValid(int r, int c) =>
      r >= 0 && r < BOARD_SIZE && c >= 0 && c < BOARD_SIZE;

  bool canPlace(int size, int r, int c, bool vertical) {
    for (int i = 0; i < size; i++) {
      int nr = vertical ? r + i : r, nc = vertical ? c : c + i;
      if (!isValid(nr, nc) || grid[nr][nc] != '.') return false;
    }
    return true;
  }

  void placeShip(int size, int r, int c, bool vertical) {
    List<List<int>> pos = [];
    for (int i = 0; i < size; i++) {
      int nr = vertical ? r + i : r, nc = vertical ? c : c + i;
      grid[nr][nc] = 'S';
      pos.add([nr, nc]);
    }
    ships.add(pos);
  }

  void placeRandom() {
    Random rand = Random();
    for (int size in SHIP_SIZES) {
      while (true) {
        int r = rand.nextInt(BOARD_SIZE), c = rand.nextInt(BOARD_SIZE);
        bool v = rand.nextBool();
        if (canPlace(size, r, c, v)) {
          placeShip(size, r, c, v);
          break;
        }
      }
    }
  }

  String shoot(int r, int c) {
    if (!isValid(r, c)) return 'OOB';
    if (grid[r][c] == 'X' || grid[r][c] == 'M') return 'ALR';
    if (grid[r][c] == 'S') {
      grid[r][c] = 'X';
      hits++;
      _checkSunk(r, c);
      return 'HIT';
    }
    grid[r][c] = 'M';
    return 'MISS';
  }

  void _checkSunk(int r, int c) {
    for (var ship in ships) {
      if (ship.any((p) => p[0] == r && p[1] == c)) {
        if (ship.every((p) => grid[p[0]][p[1]] == 'X')) shipsSunk++;
      }
    }
  }

  bool isWin() => shipsSunk == SHIP_SIZES.length;
  int get shipsRemaining => SHIP_SIZES.length - shipsSunk;

  void display({bool showShips = false}) {
    print(
      '    ' +
          List.generate(BOARD_SIZE, (i) => '${i + 1}'.padRight(2)).join(' '),
    );
    for (int r = 0; r < BOARD_SIZE; r++) {
      String rowLabel = ROWS[r];
      String cells = grid[r]
          .map((cell) {
            if (showShips && cell == 'S') return 'S ';
            return cell == 'X'
                ? 'X '
                : cell == 'M'
                ? 'M '
                : cell == '~'
                ? '~ '
                : '. ';
          })
          .join('');
      print('$rowLabel  $cells');
    }
  }
}

Map<String, dynamic> calculateAiMoveSync(List<dynamic> params) {
  var grid = params[0] as List<List<String>>;
  var available = params[1] as List<List<int>>;
  var lastHit = params[2] as List<int>?;

  List<List<int>> candidates = [];
  if (lastHit != null) {
    int r = lastHit[0], c = lastHit[1];
    for (var d in [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ]) {
      int nr = r + d[0], nc = c + d[1];
      if (nr >= 0 &&
          nr < BOARD_SIZE &&
          nc >= 0 &&
          nc < BOARD_SIZE &&
          grid[nr][nc] == '.' &&
          available.any((s) => s[0] == nr && s[1] == nc)) {
        candidates.add([nr, nc]);
      }
    }
  }
  if (candidates.isEmpty) {
    candidates = available.where((s) => grid[s[0]][s[1]] == '.').toList();
  }
  if (candidates.isEmpty) return {'result': 'ALR'};

  var shot = candidates[Random().nextInt(candidates.length)];
  return {'row': shot[0], 'col': shot[1]};
}

abstract class Player {
  Board board = Board();
  String name;
  GameStats stats;
  Player(this.name) : stats = GameStats(name);

  void placeShips() => board.placeRandom();
  Future<String> makeShot(Board opponent) => Future.value('MISS');

  void updateStats(String res, int oppSunk) {
    stats.totalShots++;
    if (res == 'HIT')
      stats.hits++;
    else
      stats.misses++;
    stats.shipsDestroyed = oppSunk;
    stats.shipsRemaining = board.shipsRemaining;
    stats.shipsLost = SHIP_SIZES.length - board.shipsRemaining;
  }
}

class Human extends Player {
  Human(String n) : super(n);

  @override
  void placeShips() {
    print('$name: "r" — случайно, иначе — вручную');
    if (stdin.readLineSync()?.toLowerCase() != 'r')
      _manualPlace();
    else
      board.placeRandom();
  }

  void _manualPlace() {
    for (int size in SHIP_SIZES) {
      while (true) {
        print('Корабль $size (пример: A1 h или A1 v):');
        board.display(showShips: true);
        var parts = stdin.readLineSync()?.trim().split(' ');
        if (parts == null || parts.isEmpty) continue;
        var pos = _parsePos(parts[0]);
        if (pos == null) {
          print('Неверные координаты!');
          continue;
        }
        bool vertical = parts.length > 1 && parts[1].toLowerCase() == 'v';
        if (!board.canPlace(size, pos[0], pos[1], vertical)) {
          print('Сюда нельзя!');
          continue;
        }
        board.placeShip(size, pos[0], pos[1], vertical);
        break;
      }
    }
  }

  List<int>? _parsePos(String s) {
    s = s.trim().toUpperCase();
    if (s.length < 2) return null;

    String letter = s[0];
    int row = ROWS.indexOf(letter);
    if (row < 0) return null;

    int? col = int.tryParse(s.substring(1));
    if (col == null || col < 1 || col > BOARD_SIZE) return null;

    return [row, col - 1];
  }

  @override
  Future<String> makeShot(Board opp) {
    while (true) {
      stdout.write('$name, выстрел (A1-J10): ');
      var input = stdin.readLineSync()?.trim() ?? '';
      var pos = _parsePos(input);
      if (pos != null) return Future.value(opp.shoot(pos[0], pos[1]));
      print('Неверно! Используйте буквы A-J и цифры 1-10 (пример: A1, J10)');
    }
  }
}

class AI extends Player {
  List<List<int>> available = [];
  List<int>? lastHit;

  AI(String n) : super(n) {
    for (int r = 0; r < BOARD_SIZE; r++)
      for (int c = 0; c < BOARD_SIZE; c++) available.add([r, c]);
  }

  @override
  Future<String> makeShot(Board opp) async {
    List<List<String>> gridCopy = opp.grid
        .map((row) => List<String>.from(row))
        .toList();
    List<List<int>> shotsCopy = available
        .map((s) => List<int>.from(s))
        .toList();
    List<int>? lastCopy = lastHit != null ? List<int>.from(lastHit!) : null;

    var result = await Isolate.run(
      () => calculateAiMoveSync([gridCopy, shotsCopy, lastCopy]),
    );

    if (result['result'] == 'ALR') return 'ALR';

    int r = result['row'] as int, c = result['col'] as int;
    available.removeWhere((s) => s[0] == r && s[1] == c);

    String res = opp.shoot(r, c);
    if (res == 'HIT') lastHit = [r, c];

    gameLogStream.add('$name: ${ROWS[r]}${c + 1} → $res');
    return res;
  }
}

class StatisticsManager {
  static final StatisticsManager _instance = StatisticsManager._internal();
  factory StatisticsManager() => _instance;
  StatisticsManager._internal();

  Future<void> saveStats(GameStats s1, GameStats s2, String winner) async {
    try {
      var dir = Directory('game_statistics');
      if (!await dir.exists()) await dir.create();

      var timestamp = DateTime.now().toString().replaceAll(
        RegExp(r'[:\-\.]'),
        '_',
      );
      var file = File('${dir.path}/battle_stats_$timestamp.txt');

      var content =
          '''
МОРСКОЙ БОЙ - СТАТИСТИКА ИГРЫ
Дата: ${DateTime.now()}
Победитель: $winner

${'=' * 50}
СТАТИСТИКА ИГРОКА 1:
${s1.toString()}

${'=' * 50}
СТАТИСТИКА ИГРОКА 2:
${s2.toString()}

${'=' * 50}
ОБЩАЯ СТАТИСТИКА:
Всего выстрелов: ${s1.totalShots + s2.totalShots}
Всего попаданий: ${s1.hits + s2.hits}
Всего промахов: ${s1.misses + s2.misses}
Общая точность: ${((s1.hits + s2.hits) / (s1.totalShots + s2.totalShots) * 100).toStringAsFixed(2)}%
''';
      await file.writeAsString(content);
      print('\nСтатистика сохранена в файл: ${file.path}');
    } catch (e) {
      print('Ошибка при сохранении статистики: $e');
    }
  }

  void displayFinalStats(GameStats s1, GameStats s2, String winner) {
    print('\n' + '=' * 60);
    print('ФИНАЛЬНАЯ СТАТИСТИКА ИГРЫ');
    print('ПОБЕДИТЕЛЬ: $winner');
    print('=' * 60);

    print('\n${s1.playerName}:');
    print('  Уничтожено кораблей противника: ${s1.shipsDestroyed}');
    print('  Потеряно кораблей: ${s1.shipsLost}');
    print('  Осталось кораблей: ${s1.shipsRemaining}/10');
    print('  Попадания/Промахи: ${s1.hits}/${s1.misses}');
    print('  Точность: ${s1.accuracy.toStringAsFixed(2)}%');

    print('\n${s2.playerName}:');
    print('  Уничтожено кораблей противника: ${s2.shipsDestroyed}');
    print('  Потеряно кораблей: ${s2.shipsLost}');
    print('  Осталось кораблей: ${s2.shipsRemaining}/10');
    print('  Попадания/Промахи: ${s2.hits}/${s2.misses}');
    print('  Точность: ${s2.accuracy.toStringAsFixed(2)}%');

    print('\nОБЩАЯ СТАТИСТИКА:');
    print('  Всего выстрелов: ${s1.totalShots + s2.totalShots}');
    print('  Всего попаданий: ${s1.hits + s2.hits}');
    print('  Всего промахов: ${s1.misses + s2.misses}');
    print(
      '  Длительность игры: ${s1.gameDuration.inMinutes} мин ${s1.gameDuration.inSeconds % 60} сек',
    );
  }
}

class Game {
  Player p1, p2;
  int turn = 1;
  List<String> log = [];
  final StatisticsManager statsManager = StatisticsManager();
  StreamSubscription<String>? sub;

  Game(this.p1, this.p2);

  Future<void> run() async {
    sub = gameLogStream.stream.listen((m) => log.add('[LOG] $m'));

    p1.stats.startGame();
    p2.stats.startGame();

    print('Морской бой! Режим: 1=против ИИ, 2=2 игрока');
    var mode = stdin.readLineSync();
    if (mode == '1') p2 = AI('ИИ');

    p1.placeShips();
    p2.placeShips();

    while (true) {
      var curr = turn == 1 ? p1 : p2;
      var opp = turn == 1 ? p2 : p1;

      print('\nХод ${curr.name}');
      if (curr is Human) {
        print('Ваше поле:');
        curr.board.display(showShips: true);
      }
      print('Поле противника:');
      opp.board.display();

      String res = await curr.makeShot(opp.board);
      curr.updateStats(res, opp.board.shipsSunk);
      opp.stats.shipsRemaining = opp.board.shipsRemaining;
      opp.stats.shipsLost = SHIP_SIZES.length - opp.board.shipsRemaining;

      var msg =
          {
            'HIT': 'Попадание!',
            'MISS': 'Промах!',
            'ALR': 'Уже стреляли!',
            'OOB': 'Вне поля!',
          }[res] ??
          'Ошибка';
      log.add('${curr.name}: $msg');
      print(msg);

      if (opp.board.isWin()) {
        p1.stats.endGame();
        p2.stats.endGame();
        print('${curr.name} победил!');

        curr.stats.shipsDestroyed = opp.board.shipsSunk;
        curr.stats.shipsRemaining = curr.board.shipsRemaining;

        statsManager.displayFinalStats(p1.stats, p2.stats, curr.name);
        await statsManager.saveStats(p1.stats, p2.stats, curr.name);

        await _end();
        return;
      }
      turn = 3 - turn;
    }
  }

  Future<void> _end() async {
    print('\nЛог игры: ${log.join('; ')}');
    print('Играть снова? д/н');
    if (stdin.readLineSync()?.toLowerCase() == 'д') {
      p1.board = Board();
      p2.board = Board();
      p1.stats = GameStats(p1.name);
      p2.stats = GameStats(p2.name);
      if (p2 is AI) p2 = AI(p2.name);
      log.clear();
      turn = 1;
      await run();
    }
    await sub?.cancel();
  }
}

Future<void> main() async {
  var p1 = Human('Игрок');
  var game = Game(p1, Human('Игрок2'));
  await game.run();
  await gameLogStream.close();
}
