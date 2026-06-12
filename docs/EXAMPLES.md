^# Примеры использования Media-MCP-Server

Практические сценарии для агентов (Cursor, Codex, Antigravity и др.), подключённых к `media-mcp-server`.

---

## Сложный сценарий: конспект и монтаж записи вебинара

Пример реалистичного запроса от контент-менеджера или студента, который сочетает видеомонтаж, аудиоанализ, компьютерное зрение (OCR, QR) и оптимизацию медиафайлов.

### Запрос пользователя

> Привет! У меня есть длинная 1,5-часовая видеозапись вчерашнего вебинара (файл `D:\Webinars\lecture_2026.mp4`). Мне нужно быстро сделать из неё краткую выжимку и конспект.
>
> Сделай, пожалуйста, следующее:
>
> 1. Проанализируй видео и найди моменты смены сцен (склейки слайдов презентации) и периоды тишины, когда лектор молчал.
> 2. Сгенерируй текстовый таймлайн лекции: для каждой смены слайда вырежи кадр, распознай на нём текст (OCR) и пришли структуру лекции с таймкодами и заголовками слайдов.
> 3. Если на слайдах есть QR-коды со ссылками на дополнительные материалы, расшифруй их и добавь ссылки в конспект.
> 4. Нарежь видео, удалив затянувшиеся паузы и технические неполадки (периоды тишины более 5 секунд), и склей оставшиеся важные фрагменты лекции в один итоговый ролик.
> 5. Сожми полученное видео до разрешения 720p в формате MP4, чтобы я мог отправить его коллегам в Telegram.

### Почему сценарий сложный и полезный

Задача экономит часы ручной работы и задействует **цепочку из 10+ инструментов** MCP-сервера:

| Этап | Инструмент | Назначение |
|------|------------|------------|
| 1. Анализ файла | `video_probe` | Кодеки, разрешение, длительность, FPS |
| 2. Структура видеоряда | `video_scene_detect` | Смена слайдов / склеек |
| 3. Анализ аудио | `video_detect_silence` | Паузы лектора (порог > 5 с) |
| 4. Ключевые кадры | `video_grab_frames` | Снимки слайдов на таймкодах сцен |
| 5. OCR | `image_detect_text` | Заголовки и текст на слайдах |
| 6. QR-ссылки | `image_read_qrcode` | Дополнительные материалы со слайдов |
| 7. Нарезка | `video_trim` | Вырезание полезных сегментов без тишины |
| 8. Склейка | `video_concat` | Единый ролик из сегментов |
| 9. Масштабирование | `video_scale` | Уменьшение до 720p |
| 10. Финализация | `video_remux` | Сборка MP4-контейнера без перекодирования (если уже H.264) |

Дополнительно агент может использовать `video_metadata_read`, `image_annotate` (подписи на превью) или `video_thumbnail` для обложки.

### Рабочий процесс агента

```mermaid
graph TD
    A[video_probe: анализ лекции] --> B[video_detect_silence: поиск тишины]
    A --> C[video_scene_detect: поиск слайдов]
    C --> D[video_grab_frames: извлечение кадров]
    D --> E[image_detect_text: распознавание заголовков]
    D --> F[image_read_qrcode: парсинг ссылок]
    B & C --> G[Расчёт таймкодов полезных сцен]
    G --> H[video_trim: нарезка сегментов]
    H --> I[video_concat: склейка видео]
    I --> J[video_scale: сжатие в 720p]
    J --> K[video_remux: финальный MP4]
    E & F --> L[Формирование MD-конспекта для пользователя]
```

### Пример последовательности вызовов MCP

Ниже — упрощённая иллюстрация того, как агент может вызывать tools (параметры подставляются из результатов предыдущих шагов):

```json
{"name": "video_probe", "arguments": {"sourceUrl": "D:\\Webinars\\lecture_2026.mp4"}}
```

```json
{"name": "video_scene_detect", "arguments": {"sourceUrl": "D:\\Webinars\\lecture_2026.mp4", "threshold": 0.3}}
```

```json
{"name": "video_detect_silence", "arguments": {"sourceUrl": "D:\\Webinars\\lecture_2026.mp4", "minSilenceMs": 5000}}
```

```json
{"name": "video_grab_frames", "arguments": {
  "sourceUrl": "D:\\Webinars\\lecture_2026.mp4",
  "timeOffsetsMs": [0, 125000, 340000, 890000],
  "outputDir": "data/media/captures/lecture_2026"
}}
```

```json
{"name": "image_detect_text", "arguments": {"imagePath": "data/media/captures/lecture_2026/frame_125000.jpg"}}
```

```json
{"name": "image_read_qrcode", "arguments": {"imagePath": "data/media/captures/lecture_2026/frame_340000.jpg"}}
```

```json
{"name": "video_trim", "arguments": {
  "sourceUrl": "D:\\Webinars\\lecture_2026.mp4",
  "outputPath": "data/media/video/seg_01.mp4",
  "startMs": 120000,
  "endMs": 335000
}}
```

```json
{"name": "video_concat", "arguments": {
  "inputPaths": ["data/media/video/seg_01.mp4", "data/media/video/seg_02.mp4"],
  "outputPath": "data/media/video/lecture_cut.mp4"
}}
```

```json
{"name": "video_scale", "arguments": {
  "sourceUrl": "data/media/video/lecture_cut.mp4",
  "outputPath": "data/media/video/lecture_720p.mp4",
  "width": 1280,
  "height": 720
}}
```

```json
{"name": "video_remux", "arguments": {
  "sourceUrl": "data/media/video/lecture_720p.mp4",
  "outputPath": "data/media/output/lecture_2026_telegram.mp4"
}}
```

### Ожидаемый результат для пользователя

1. **Markdown-конспект** с разделами по слайдам, таймкодами, OCR-заголовками и QR-ссылками.
2. **Сокращённое видео** `lecture_2026_telegram.mp4` в 720p без длинных пауз.
3. **Промежуточные артефакты** в `data/media/` (кадры, сегменты) — при необходимости для проверки.

### Практические замечания

- **Пути:** используйте абсолютные пути к исходному файлу; выходные файлы можно класть в `data/media/` (или `MEDIA_MCP_DATA_PATH`).
- **Длительность:** 1,5-часовое видео — тяжёлая задача; `video_scale` перекодирует поток, это может занять время.
- **Тишина vs сцены:** пересечение интервалов из `video_detect_silence` и `video_scene_detect` агент вычисляет сам — сервер возвращает сырые таймкоды.
- **OCR:** для слайдов с мелким текстом попробуйте `image_detect_text_east` как альтернативу.
- **HTTP-режим:** для длительных пайплайнов удобно держать сервер в Streamable HTTP (`.\bin\launch_http.cmd`) и увеличить `tool_timeout_sec` в Codex.

### Как воспроизвести сценарий

1. Подключите MCP-сервер — см. [INSTALLATION.md](INSTALLATION.md).
2. Откройте workspace с доступом к `D:\Webinars\lecture_2026.mp4` (или скопируйте файл в `data/media/video/`).
3. Вставьте **запрос пользователя** (блок выше) в чат агента.
4. Агент выполнит цепочку tools и вернёт конспект + путь к итоговому MP4.

---

## Сложный сценарий: ночная смена на складе (ONVIF + RTSP)

Пример для администратора безопасности или диспетчера, который работает с **несколькими IP-камерами** в локальной сети: обнаружение устройств по ONVIF, получение RTSP-потоков, проверка доступности, съём кадров, анализ объектов/лиц, запись фрагмента инцидента и отчёт.

### Запрос пользователя

> Я дежурный на складе. В сети должны быть три ONVIF-камеры: вход (`Entrance`), погрузочная зона (`LoadingDock`) и парковка (`Parking`). Логин/пароль ONVIF: `admin` / `***` (подставь из vault).
>
> Нужен отчёт за ночную смену (22:00–06:00):
>
> 1. Найди все камеры в подсети и получи для каждой **RTSP URI** основного потока.
> 2. Проверь, что потоки доступны, и выведи разрешение, FPS и кодек по каждой камере.
> 3. На камере `LoadingDock` (PTZ) сделай обход: поверни направо 3 секунды, останови, сними кадр; затем влево 3 секунды, останови, сними кадр.
> 4. Со всех трёх камер сними текущие кадры и проверь: есть ли люди или транспорт (`person`, `car`, `truck`). Сравни лица у входа со списком сотрудников из `data/media/faces/`.
> 5. Около **02:30** на `LoadingDock` зафиксировано движение. Запиши **90 секунд** RTSP-архива с этой камеры (можно взять live-поток сейчас как демо) и найди в записи смены сцен / резкие изменения кадра.
> 6. На кадре с максимальной активностью обведи найденные объекты и собери **Markdown-отчёт**: таблица камер, статус потоков, тревоги, пути к снимкам и MP4.

### Почему сценарий сложный и полезный

Задача типична для **видеонаблюдения и IoT**: нужно связать discovery, управление камерой и аналитику потока. Задействуется **цепочка из 12+ инструментов**:

| Этап | Инструмент | Назначение |
|------|------------|------------|
| 1. Discovery | `camera_discover` | Поиск ONVIF-устройств в LAN (multicast WS-Discovery) |
| 2. RTSP URL | `camera_get_stream_uri` | RTSP-адрес по `cameraIp` + учётные данные |
| 3. Доступность | `stream_test` | Проверка RTSP/HTTP, задержка подключения |
| 4. Параметры потока | `video_probe` | Кодек, разрешение, FPS, аудио/видео-потоки |
| 5. PTZ-обход | `camera_ptz_move`, `camera_ptz_stop` | Поворот PTZ-камеры на LoadingDock |
| 6. Настройка изображения | `camera_get_imaging_settings` | Яркость/контраст (опционально `camera_set_imaging_settings`) |
| 7. Снимки | `video_grab_frame` | JPEG с RTSP `sourceUrl` |
| 8. Детекция | `image_detect_objects` | Люди, авто (COCO/YOLOX) |
| 9. Идентификация | `face_identify`, `face_list` | Сверка с эталонами в `data/media/faces/` |
| 10. Архив | `video_record_segment` | Запись фрагмента RTSP (stream copy) |
| 11. Аналитика записи | `video_scene_detect` | Смены сцен в MP4-фрагменте |
| 12. Отчёт | `image_annotate`, `video_thumbnail` | Разметка тревожного кадра, превью клипа |

FFmpeg внутри сервера подключается к RTSP с транспортом **TCP** (`rtsp_transport=tcp`) — стабильнее в корпоративных сетях, чем UDP.

### Рабочий процесс агента

```mermaid
graph TD
    A[camera_discover: поиск ONVIF] --> B[camera_get_stream_uri x3]
    B --> C[stream_test: проверка RTSP]
    C --> D[video_probe: кодеки и FPS]
    D --> E[camera_ptz_move / stop: обход LoadingDock]
    E --> F[video_grab_frame: снимки с 3 камер]
    F --> G[image_detect_objects: люди и транспорт]
    F --> H[face_identify: сверка сотрудников]
    D --> I[video_record_segment: архив 90 с]
    I --> J[video_scene_detect: события в записи]
    G & J --> K[image_annotate: тревожный кадр]
    K & I --> L[Markdown-отчёт дежурного]
```

### Пример последовательности вызовов MCP

**1. Обнаружение и RTSP**

```json
{"name": "camera_discover", "arguments": {}}
```

```json
{"name": "camera_get_stream_uri", "arguments": {
  "cameraIp": "http://192.168.10.51/onvif/device_service",
  "username": "admin",
  "password": "YOUR_PASSWORD"
}}
```

Ответ содержит `rtspUri`, например: `rtsp://192.168.10.51:554/Streaming/Channels/101`

**2. Проверка и анализ потока**

```json
{"name": "stream_test", "arguments": {
  "sourceUrl": "rtsp://192.168.10.51:554/Streaming/Channels/101",
  "timeoutMs": 10000
}}
```

```json
{"name": "video_probe", "arguments": {
  "sourceUrl": "rtsp://192.168.10.51:554/Streaming/Channels/101"
}}
```

**3. PTZ-обход (камера LoadingDock, `192.168.10.52`)**

```json
{"name": "camera_ptz_move", "arguments": {
  "cameraIp": "http://192.168.10.52/onvif/device_service",
  "username": "admin",
  "password": "YOUR_PASSWORD",
  "pan": 0.5,
  "tilt": 0.0,
  "zoom": 0.0,
  "timeoutMs": 3000
}}
```

```json
{"name": "camera_ptz_stop", "arguments": {
  "cameraIp": "http://192.168.10.52/onvif/device_service",
  "username": "admin",
  "password": "YOUR_PASSWORD"
}}
```

Повторить с `"pan": -0.5` для второго ракурса.

**4. Снимки и аналитика**

```json
{"name": "video_grab_frame", "arguments": {
  "sourceUrl": "rtsp://192.168.10.51:554/Streaming/Channels/101",
  "outputPath": "data/media/captures/entrance_night.jpg",
  "timeOffsetMs": 0
}}
```

```json
{"name": "image_detect_objects", "arguments": {
  "imagePath": "data/media/captures/entrance_night.jpg"
}}
```

```json
{"name": "face_list", "arguments": {}}
```

```json
{"name": "face_identify", "arguments": {
  "imagePath": "data/media/captures/entrance_night.jpg",
  "threshold": 0.6
}}
```

**5. Запись фрагмента и поиск событий**

```json
{"name": "video_record_segment", "arguments": {
  "sourceUrl": "rtsp://192.168.10.52:554/Streaming/Channels/101",
  "outputPath": "data/media/video/loadingdock_incident.mp4",
  "durationMs": 90000
}}
```

```json
{"name": "video_scene_detect", "arguments": {
  "sourceUrl": "data/media/video/loadingdock_incident.mp4",
  "threshold": 0.35
}}
```

**6. Разметка и превью для отчёта**

```json
{"name": "image_annotate", "arguments": {
  "imagePath": "data/media/captures/loadingdock_alert.jpg",
  "outputPath": "data/media/output/loadingdock_alert_marked.jpg",
  "labels": ["person", "truck"],
  "boxes": [[120, 80, 200, 400], [450, 200, 320, 180]]
}}
```

```json
{"name": "video_thumbnail", "arguments": {
  "sourceUrl": "data/media/video/loadingdock_incident.mp4",
  "outputPath": "data/media/output/loadingdock_thumb.jpg",
  "timeOffsetMs": 45000
}}
```

### Ожидаемый результат для пользователя

1. **Таблица камер** — IP, имя из ONVIF scopes, RTSP URI, статус `stream_test`, разрешение/FPS.
2. **Блок «Тревоги»** — камера, время, класс объекта, `face_identify` (сотрудник / неизвестный).
3. **Файлы** — снимки в `data/media/captures/`, MP4 в `data/media/video/`, размеченный кадр в `data/media/output/`.
4. **Markdown-отчёт** для передачи смены утренней бригаде.

### Практические замечания

- **Сеть:** MCP-сервер должен иметь доступ к подсети камер (тот же VLAN/VPN). Multicast для `camera_discover` может блокироваться Wi‑Fi изоляцией или корпоративным firewall.
- **Учётные данные:** передавайте `username`/`password` в tools или храните в env агента; не коммитьте пароли в репозиторий.
- **`cameraIp`:** используйте `xaddr` из `camera_discover` (например `http://192.168.10.51/onvif/device_service`), не путать с RTSP URL.
- **Прямой RTSP:** если URI уже известен (`rtsp://user:pass@host/...`), можно пропустить ONVIF и сразу вызывать `stream_test` / `video_grab_frame`.
- **Запись с live-потока:** `video_record_segment` пишет **текущий** поток; для архива «02:30» нужен NVR с playback URL или заранее записанный файл. Агент может пояснить это пользователю и записать демо-фрагмент с live RTSP.
- **Таймауты:** RTSP и запись 90 с — долгие операции; в HTTP-режиме увеличьте `tool_timeout_sec` в Codex или держите stdio-сессию.
- **Эталоны лиц:** заранее выполните `face_enroll` для сотрудников допуска на склад.

### Как воспроизвести сценарий

1. Подключите MCP — [INSTALLATION.md](INSTALLATION.md). Для длительных RTSP-задач удобен `.\bin\launch_http.cmd`.
2. Убедитесь, что ПК видит камеры (`ping`, ONVIF Device Manager — опционально).
3. Заполните эталоны: `face_enroll` для 2–3 тестовых фото в `data/media/faces/`.
4. Вставьте **запрос пользователя** в чат агента, подставив реальные IP и пароль.
5. Агент построит pipeline и вернёт отчёт с путями к артефактам.

### Упрощённый вариант (одна известная RTSP-камера)

Если ONVIF не нужен:

```json
{"name": "stream_test", "arguments": {"sourceUrl": "rtsp://192.168.1.100:554/stream1"}}
```

```json
{"name": "video_grab_frame", "arguments": {
  "sourceUrl": "rtsp://192.168.1.100:554/stream1",
  "outputPath": "data/media/captures/snapshot.jpg"
}}
```

```json
{"name": "image_detect_objects", "arguments": {"imagePath": "data/media/captures/snapshot.jpg"}}
```

---

## Сложный сценарий: умный контроль доступа и мониторинг рабочего места (USB webcam)

Пример для администратора офиса или разработчика IoT, который работает с **локальной USB/встроенной веб-камерой** на том же ПК, где запущен MCP-сервер: калибровка камеры, регистрация лиц, проверка доступа, запись активности, трекинг объекта и итоговый отчёт.

### Запрос пользователя

> Я настраиваю систему контроля доступа в небольшой переговорной. Используй **media-mcp-server** и локальную веб-камеру на этом ПК. Все артефакты сохраняй в `data/media/` (подпапки `captures/`, `video/`, `output/`, `faces/`).
>
> **Этап 1 — обнаружение и калибровка камеры**
>
> 1. Найди все доступные веб-камеры (`webcam_list`) и выбери основную (обычно индекс 0). Если камера не открывается с backend `any`, попробуй `dshow`, затем `msmf`.
> 2. Сними три тестовых кадра в 1280×720 с разными настройками экспозиции:
>    - «тёмный» — `brightness: 0.3`, `contrast: 0.5`
>    - «нормальный» — без дополнительных параметров
>    - «яркий» — `brightness: 0.8`, `contrast: 0.7`
> 3. Сравни кадры визуально (прочитай сохранённые JPEG) и выбери лучший для дальнейшей работы. Зафиксируй итоговые параметры.
>
> **Этап 2 — регистрация сотрудников (face registry)**
>
> 4. Проверь, кто уже зарегистрирован (`face_list`).
> 5. Если в реестре нет имён **«Алексей»** и **«Мария»**, попроси меня встать перед камерой по очереди и для каждого:
>    - сними кадр с выбранными настройками;
>    - убедись, что на кадре ровно одно лицо (`image_detect_faces`);
>    - зарегистрируй лицо (`face_enroll`).
> 6. Если лицо не найдено или их больше одного — повтори съёмку и сообщи причину.
>
> **Этап 3 — проверка доступа «у двери»**
>
> 7. Сними текущий кадр «как будто человек подошёл к двери».
> 8. Выполни полный анализ кадра:
>    - `image_detect_faces` — количество и координаты лиц;
>    - `face_identify` (порог `0.65`) — кто из зарегистрированных;
>    - `image_detect_objects` — есть ли посторонние предметы (`backpack`, `laptop`, `cell phone`, `bottle` и т.д.);
>    - `image_read_qrcode` — если я покажу бейдж с QR, расшифруй его.
> 9. Прими решение:
>    - **ДОПУСК** — лицо идентифицировано, посторонних лиц нет;
>    - **ОТКАЗ** — неизвестное лицо или несколько лиц;
>    - **ПРОВЕРКА** — лицо распознано, но обнаружены подозрительные объекты.
> 10. Сохрани размеченный кадр (`image_annotate`) с рамками лиц, объектов и подписью решения.
>
> **Этап 4 — мониторинг активности за 15 секунд**
>
> 11. Запиши 15-секундное видео с камеры (`webcam_record_video`, 1280×720, 25 fps, `durationMs: 15000`).
> 12. Найди смены сцен в записи (`video_scene_detect`, `threshold: 0.25`) — резкие движения, вход/выход человека.
> 13. Извлеки ключевые кадры: первый, последний и по одному на каждую смену сцены (`video_grab_frames` или отдельные `video_grab_frame` с `timeOffsetMs`).
> 14. Между первым и последним кадром вычисли оптический поток (`image_optical_flow`) — оцени, насколько активно было движение в комнате.
>
> **Этап 5 — трекинг объекта в live-потоке**
>
> 15. Сними кадр, на котором я держу в руке предмет (ручка, телефон, чашка).
> 16. По результату `image_detect_objects` возьми bounding box самого крупного объекта в руке.
> 17. Запусти трекинг этого объекта в live-потоке (`video_track_object`, 60 кадров) и сохрани результат в `data/media/video/tracked_object.mp4`.
> 18. Если объект не найден — попроси меня поднести его ближе к камере и повтори.
>
> **Этап 6 — итоговый отчёт**
>
> 19. Собери **Markdown-отчёт** со структурой:
>    - таблица найденных камер и выбранных настроек;
>    - список зарегистрированных лиц;
>    - результат проверки доступа (решение + уверенность `face_identify`);
>    - обнаруженные объекты и QR (если был);
>    - таймлайн активности по `video_scene_detect`;
>    - оценка движения по optical flow;
>    - результат трекинга объекта;
>    - **полные пути** ко всем файлам в `data/media/`.
> 20. Если на каком-то шаге tool вернул `error`, не останавливайся — зафиксируй ошибку в отчёте и предложи обходной путь (другой backend, другое разрешение, повторная съёмка).

### Почему сценарий сложный и полезный

Задача типична для **умного офиса и контроля доступа** без IP-камер: нужно связать калибровку USB-устройства, биометрию, детекцию предметов и анализ движения в одном пайплайне. Задействуется **цепочка из 15+ инструментов** с ветвлением по результатам:

| Этап | Инструмент | Назначение |
|------|------------|------------|
| 1. Discovery | `webcam_list` | Поиск USB/встроенных камер по индексам |
| 2. Калибровка | `webcam_grab_frame` | Съёмка с яркостью, контрастом, backend (`dshow`/`msmf`) |
| 3. Реестр | `face_list` | Текущие зарегистрированные лица |
| 4. Валидация | `image_detect_faces` | Проверка «ровно одно лицо» перед enroll |
| 5. Регистрация | `face_enroll` | Добавление сотрудника в локальный реестр |
| 6. Идентификация | `face_identify` | Сверка при проверке доступа |
| 7. Детекция | `image_detect_objects` | Предметы в кадре (COCO/YOLOX) |
| 8. QR-бейдж | `image_read_qrcode` | Расшифровка QR на пропуске |
| 9. Разметка | `image_annotate` | Визуальный отчёт с рамками и подписью |
| 10. Запись | `webcam_record_video` | 15 с видео без GUI |
| 11. События | `video_scene_detect` | Смены сцен / резкие движения |
| 12. Ключевые кадры | `video_grab_frame`, `video_grab_frames` | Снимки на таймкодах |
| 13. Движение | `image_optical_flow` | Optical flow между первым и последним кадром |
| 14. Трекинг | `video_track_object` | TrackerNano в live-потоке webcam |

### Рабочий процесс агента

```mermaid
graph TD
    A[webcam_list] --> B[webcam_grab_frame x3: калибровка]
    B --> C[Выбор лучших настроек]
    C --> D[face_list]
    D --> E{Нужен enroll?}
    E -->|да| F[webcam_grab_frame + image_detect_faces]
    F --> G[face_enroll]
    E -->|нет| H[Кадр «у двери»]
    G --> H
    H --> I[face_identify + image_detect_objects + image_read_qrcode]
    I --> J[Решение: ДОПУСК / ОТКАЗ / ПРОВЕРКА]
    J --> K[image_annotate]
    K --> L[webcam_record_video 15с]
    L --> M[video_scene_detect]
    M --> N[video_grab_frames + image_optical_flow]
    N --> O[webcam_grab_frame + image_detect_objects]
    O --> P[video_track_object]
    P --> Q[Markdown-отчёт]
```

### Пример последовательности вызовов MCP

**1. Обнаружение и калибровка**

```json
{"name": "webcam_list", "arguments": {}}
```

```json
{"name": "webcam_grab_frame", "arguments": {
  "cameraIndex": 0,
  "outputPath": "data/media/captures/calib_normal.jpg",
  "width": 1280,
  "height": 720,
  "backend": "dshow"
}}
```

```json
{"name": "webcam_grab_frame", "arguments": {
  "cameraIndex": 0,
  "outputPath": "data/media/captures/calib_dark.jpg",
  "width": 1280,
  "height": 720,
  "backend": "dshow",
  "brightness": 0.3,
  "contrast": 0.5
}}
```

**2. Регистрация и проверка лица**

```json
{"name": "face_list", "arguments": {}}
```

```json
{"name": "image_detect_faces", "arguments": {
  "imagePath": "data/media/captures/enroll_alexey.jpg"
}}
```

```json
{"name": "face_enroll", "arguments": {
  "imagePath": "data/media/captures/enroll_alexey.jpg",
  "name": "Алексей"
}}
```

```json
{"name": "face_identify", "arguments": {
  "imagePath": "data/media/captures/door_check.jpg",
  "threshold": 0.65
}}
```

**3. Анализ кадра и разметка**

```json
{"name": "image_detect_objects", "arguments": {
  "imagePath": "data/media/captures/door_check.jpg"
}}
```

```json
{"name": "image_read_qrcode", "arguments": {
  "imagePath": "data/media/captures/door_check.jpg"
}}
```

```json
{"name": "image_annotate", "arguments": {
  "imagePath": "data/media/captures/door_check.jpg",
  "outputPath": "data/media/output/door_check_marked.jpg",
  "labels": ["Алексей", "laptop"],
  "boxes": [[180, 90, 220, 280], [520, 310, 180, 120]]
}}
```

**4. Запись активности и анализ движения**

```json
{"name": "webcam_record_video", "arguments": {
  "cameraIndex": 0,
  "outputPath": "data/media/video/room_activity.mp4",
  "durationMs": 15000,
  "width": 1280,
  "height": 720,
  "fps": 25,
  "backend": "dshow"
}}
```

```json
{"name": "video_scene_detect", "arguments": {
  "sourceUrl": "data/media/video/room_activity.mp4",
  "threshold": 0.25
}}
```

```json
{"name": "image_optical_flow", "arguments": {
  "imagePath1": "data/media/captures/activity_first.jpg",
  "imagePath2": "data/media/captures/activity_last.jpg",
  "outputPath": "data/media/output/activity_flow.jpg"
}}
```

**5. Трекинг объекта в live-потоке**

```json
{"name": "video_track_object", "arguments": {
  "cameraIndex": 0,
  "x": 420,
  "y": 180,
  "width": 95,
  "height": 140,
  "frameCount": 60,
  "outputPath": "data/media/video/tracked_object.mp4",
  "backend": "dshow"
}}
```

### Ожидаемый результат для пользователя

1. **Markdown-отчёт** — решение по доступу (ДОПУСК / ОТКАЗ / ПРОВЕРКА), таблица камер, таймлайн активности.
2. **Калибровочные снимки** в `data/media/captures/` (тёмный / нормальный / яркий).
3. **Размеченный кадр** проверки доступа в `data/media/output/`.
4. **Видео** активности и трекинга в `data/media/video/`.
5. **Зарегистрированные лица** в `data/media/faces/` (после `face_enroll`).

### Практические замечания

- **Пути:** `outputPath` в `webcam_grab_frame` и `webcam_record_video` должен быть **абсолютным**; в примерах выше — относительные пути в `data/media/` (корень задаётся `MEDIA_MCP_DATA_PATH` или рабочая директория сервера).
- **Windows:** для USB-камер чаще стабилен backend `dshow`; при ошибке открытия попробуйте `msmf` или `any`.
- **Первый кадр:** после открытия камеры первый кадр иногда получается тёмным — при плохом качестве повторите `webcam_grab_frame`.
- **`face_enroll`:** требуется ровно одно чёткое лицо; при нескольких лицах enroll не выполняйте.
- **Интерактивность:** на шагах регистрации, проверки доступа и трекинга агент должен **попросить пользователя** встать перед камерой или показать предмет.
- **Таймауты:** `webcam_record_video` (15 с) и `video_track_object` (60 кадров) — долгие операции; в HTTP-режиме увеличьте `tool_timeout_sec` в Codex.
- **Тест:** скрипт `scripts/tests/test_webcam_mcp.ps1` проверяет цепочку `webcam_grab_frame` → `image_detect_faces` → `image_detect_objects` → `face_identify`.

### Как воспроизвести сценарий

1. Подключите MCP-сервер — см. [INSTALLATION.md](INSTALLATION.md).
2. Убедитесь, что к ПК подключена веб-камера и она не занята другим приложением (Zoom, Teams).
3. Вставьте **запрос пользователя** (блок выше) в чат агента.
4. Следуйте подсказкам агента: встаньте перед камерой для enroll и проверки доступа, покажите предмет для трекинга.
5. Агент выполнит цепочку tools и вернёт отчёт с путями к артефактам.

### Упрощённый вариант (быстрая проверка камеры)

Если нужен короткий smoke-test без полного пайплайна:

> Подключись к media-mcp-server: найди веб-камеры (`webcam_list`), сними кадр с индекса 0 (`webcam_grab_frame`), найди лица и объекты (`image_detect_faces`, `image_detect_objects`), попробуй `face_identify` с порогом 0.7. Выведи JSON-результаты и путь к сохранённому JPEG.

```json
{"name": "webcam_list", "arguments": {}}
```

```json
{"name": "webcam_grab_frame", "arguments": {
  "cameraIndex": 0,
  "outputPath": "data/media/captures/webcam_now.jpg",
  "backend": "dshow"
}}
```

```json
{"name": "image_detect_faces", "arguments": {"imagePath": "data/media/captures/webcam_now.jpg"}}
```

```json
{"name": "image_detect_objects", "arguments": {"imagePath": "data/media/captures/webcam_now.jpg"}}
```

```json
{"name": "face_identify", "arguments": {
  "imagePath": "data/media/captures/webcam_now.jpg",
  "threshold": 0.7
}}
```

---

## Другие идеи для промптов

| Сценарий | Ключевые tools |
|----------|----------------|
| Контроль доступа / мониторинг офиса (USB) | см. сценарий выше |
| Одна ONVIF-камера | `camera_discover`, `camera_get_stream_uri`, `video_grab_frame` |
| Склад / периметр (RTSP) | см. сценарий выше |
| Подготовка клипа для соцсетей | `video_probe`, `video_trim`, `video_scale`, `video_thumbnail` |
| Разметка объектов на фото | `image_detect_objects`, `image_annotate` |

Полный список из 47 инструментов — в [README.md](../README.md#tools-47).
