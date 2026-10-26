// Операции с фрагментами (задачи 3.4.1–3.4.3) поверх потока UDP после
// сведения узлов (задача 3.7.4): те же тесты, что в паре в памяти и по
// TCP, — соединение клиента с узлом идёт через UdpEndpoint на loopback.

import 'peer_service_test.dart';

void main() => peerServiceTests(udp: true);
