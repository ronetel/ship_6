добавили три асинхронные технологии Dart: **Future**, **Stream** и **Isolate**

---

## 1. Future и async/await

- Метод `makeShot()` у ИИ возвращает `Future<String>`, потому что ход вычисляется в изоляте
- Метод `run()` в классе `Game` помечен как `async`, чтобы использовать `await`
- Метод `saveStats()` в `StatisticsManager` асинхронно записывает файл

Нужно чтобы программа не зависала, пока ИИ думает или пока статистика сохраняется в файл.

**Пример:**
```
String res = await curr.makeShot(opp.board);  // ждём результат выстрела
await statsManager.saveStats(...);            // ждём запись файла
```

---

## 2. Stream

- Создали `StreamController<String> gameLogStream` для передачи логов игры
- В `AI.makeShot()` публикуются события: `gameLogStream.add(...)`
- В `Game.run()` подписываемся на стрим: `gameLogStream.stream.listen(...)`
- В конце игры отменяем подписку: `await sub?.cancel()`

Нужно чтобы логировать действия ИИ без прямого вызова методов. ИИ просто отправляет событие в стрим, а игра его записывает в лог.

**Пример:**
```
// Публикация события (в AI)
gameLogStream.add('$name: ${ROWS[r]}${c + 1} → $res');

// Подписка на событие (в Game)
sub = gameLogStream.stream.listen((m) => log.add('[LOG] $m'));
```

---

## 3. Isolate

- `calculateAiMoveSync()` функция для изолята
- В `AI.makeShot()` запускаем изолят: `await Isolate.run(() => calculateAiMoveSync(...))`

Нужно чтобы логика выбора хода ИИ юыла вынесена в отдельный поток. Пока выполняется действия ИИ, основной поток не зависает.

**Пример:**
```
// Функция для изолята (вне класса!)
Map<String, dynamic> calculateAiMoveSync(List<dynamic> params) {
  // логика выбора хода
  return {'row': shot[0], 'col': shot[1]};
}

// Запуск в AI.makeShot()
var result = await Isolate.run(
  () => calculateAiMoveSync([gridCopy, shotsCopy, lastCopy])
);
```
