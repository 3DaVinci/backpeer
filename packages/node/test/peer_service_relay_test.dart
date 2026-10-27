// Операции с фрагментами (задачи 3.4.1–3.4.3) через relay (задача 3.8.1):
// те же тесты, что в паре в памяти и поверх UDP, — узел и клиент оба без
// входящих соединений, каждый только подключается к relay на loopback.

import 'peer_service_test.dart';

void main() => peerServiceTests(relay: true);
