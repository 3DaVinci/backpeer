## 0.0.8-dev.0

 - Bump version to keep all packages in the workspace in lockstep.

## 0.0.7

 - Graduate package to a stable release. See pre-releases prior to this version for changelog entries.

## 0.0.7-dev.2

 - Bump version to keep all packages in the workspace in lockstep.

## 0.0.7-dev.1

 - Bump version to keep all packages in the workspace in lockstep.

## 0.0.7-dev.0

 - **FEAT**(app,agent,core,coordinator): прогресс, бэкап отдельной папки и скорость бэкапа.

## 0.0.6

 - Bump version to keep all packages in the workspace in lockstep.

## 0.0.5-dev.0

 - Bump version to keep all packages in the workspace in lockstep.

## 0.0.4

 - Bump "coordinator" to `0.0.4`.

## 0.0.3-dev.5

 - **FEAT**(coordinator,app): минимум ёмкости хранителя 10 ГБ вместо 100 ГБ.

## 0.0.3-dev.4

 - Bump version to keep all packages in the workspace in lockstep.

## 0.0.3-dev.3

 - Bump version to keep all packages in the workspace in lockstep.

## 0.0.3-dev.2

 - Bump version to keep all packages in the workspace in lockstep.

## 0.0.3-dev.1

 - Bump version to keep all packages in the workspace in lockstep.

## 0.0.3-dev.0

 - **PERF**(coordinator): фаззинг API, нагрузочный тест, исправление взаимоблокировки (2.9.2, 2.9.3).
 - **FIX**(coordinator,repo): доверять X-Forwarded-For за прокси на стенде.
 - **FIX**(coordinator,repo): CORS сводки о сети и разбор справочника DB-IP.
 - **FIX**(coordinator): порт стенда 8090 вместо 8080.
 - **FEAT**(agent): хранитель службой ОС, сон и сеть, удаление клиента (5.6.1, 5.6.3, 5.6.4).
 - **FEAT**: verify по аудитам, тестовое восстановление выборки и история проверок (4.5.2).
 - **FEAT**: сводка здоровья бэкапа от координатора и cli status (4.5.1).
 - **FEAT**: выход узла, перенос фрагментов и сверка с координатором (4.4).
 - **FEAT**(coordinator): метрики ремонта в coordinator admin repair stats (4.3.6).
 - **FEAT**(coordinator): проверка результата ремонта аудитом (4.3.5).
 - **FEAT**: исполнитель ремонта на узле и задания ремонта на координаторе (4.3.4).
 - **FEAT**(coordinator): очередь ремонта с приоритетом и пределом трафика (4.3.2).
 - **FEAT**(coordinator): учёт живых фрагментов сегментов (4.3.1).
 - **FEAT**(site,ci): страница загрузок приложений и образов Docker.
 - **FEAT**(agent): поиск, версии, восстановление выбранного, роль хранителя (5.4, 5.5).
 - **FEAT**(coordinator,node): сведения координатора об узле в heartbeat, папка фрагментов (5.5).
 - **FEAT**(agent): расписание, оценка объёма, история, здоровье, политика хранения (5.3).
 - **FEAT**(agent): учётная запись и устройства в локальном API (5.2).
 - **FEAT**(agent): агент бэкапа и ключи в хранилище ОС (5.1.3, 5.1.4).
 - **FEAT**(node): Docker-образ узла и стенд с узлами (3.10.1).
 - **FEAT**(coordinator): репутация узла в размещении, испытательный срок (4.2).
 - **FEAT**(coordinator): аудиты хранения — спецификация, ответ узла, планировщик (4.1).
 - **FEAT**(core): сеть на стороне клиента — Transport, NetworkFragmentStore, ожидание узлов (3.9).
 - **FEAT**(relay): relay-сервер, пропуска координатора и метрики (3.8).
 - **FEAT**(node): сведение узлов и надёжный поток поверх UDP (3.7.2–3.7.4).
 - **FEAT**(coordinator): основа сервера — API, FS-Auth, PostgreSQL, пределы частоты (задачи 2.1.2–2.1.5).
 - **FEAT**(node): приём TCP, проверка достижимости, проброс порта (3.5).
 - **FEAT**(site,coordinator): блок «Сеть сейчас» и карта хостов по geoip.
 - **FEAT**(core): канал Noise XX, проверка собеседника, кадры и фаззинг (3.3).
 - **FEAT**(node): хранилище фрагментов, индекс, квота, проверка целостности (3.2).
 - **FEAT**(node): демон хранителя, регистрация у координатора, локальный API (3.1).
 - **FEAT**(node): привязка узла по коду, Docker-образ и systemd (этап 6).
 - **FEAT**(coordinator): административный CLI, журнал действий (2.10).
 - **FEAT**(cli): работа через координатор, вход по паролю, устройства (2.8.2, 2.8.3).
 - **FEAT**(coordinator): размещение сегментов, талоны через подписанта (2.7).
 - **FEAT**(coordinator): объекты, реестр узлов, доступность, размещение (2.5, 2.6, 2.7.1).
 - **FEAT**(coordinator): учётные записи, устройства, отзывы, вход по паролю (2.2.2, 2.3, 2.4.2).
 - **FEAT**(coordinator): процесс-подписант талонов на Unix-сокете (задача 2.2.1).
 - **FEAT**(node): канал команд координатора по WebSocket (3.6).

## 0.0.2

 - **PERF**(coordinator): фаззинг API, нагрузочный тест, исправление взаимоблокировки (2.9.2, 2.9.3).
 - **FIX**(coordinator): порт стенда 8090 вместо 8080.
 - **FEAT**(node): Docker-образ узла и стенд с узлами (3.10.1).
 - **FEAT**(coordinator): репутация узла в размещении, испытательный срок (4.2).
 - **FEAT**(coordinator): аудиты хранения — спецификация, ответ узла, планировщик (4.1).
 - **FEAT**(core): сеть на стороне клиента — Transport, NetworkFragmentStore, ожидание узлов (3.9).
 - **FEAT**(relay): relay-сервер, пропуска координатора и метрики (3.8).
 - **FEAT**(node): сведение узлов и надёжный поток поверх UDP (3.7.2–3.7.4).
 - **FEAT**(node): канал команд координатора по WebSocket (3.6).
 - **FEAT**(node): приём TCP, проверка достижимости, проброс порта (3.5).
 - **FEAT**(core): канал Noise XX, проверка собеседника, кадры и фаззинг (3.3).
 - **FEAT**(node): хранилище фрагментов, индекс, квота, проверка целостности (3.2).
 - **FEAT**(node): демон хранителя, регистрация у координатора, локальный API (3.1).
 - **FEAT**(coordinator): административный CLI, журнал действий (2.10).
 - **FEAT**(cli): работа через координатор, вход по паролю, устройства (2.8.2, 2.8.3).
 - **FEAT**(coordinator): размещение сегментов, талоны через подписанта (2.7).
 - **FEAT**(coordinator): объекты, реестр узлов, доступность, размещение (2.5, 2.6, 2.7.1).
 - **FEAT**(coordinator): учётные записи, устройства, отзывы, вход по паролю (2.2.2, 2.3, 2.4.2).
 - **FEAT**(coordinator): процесс-подписант талонов на Unix-сокете (задача 2.2.1).
 - **FEAT**(coordinator): основа сервера — API, FS-Auth, PostgreSQL, пределы частоты (задачи 2.1.2–2.1.5).

