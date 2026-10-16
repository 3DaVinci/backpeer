import 'package:app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App starts', (tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('Not implemented yet'), findsOneWidget);
  });
}
