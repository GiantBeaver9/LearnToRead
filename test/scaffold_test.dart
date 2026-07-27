import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/main.dart';

void main() {
  testWidgets('scaffold: app shell boots', (tester) async {
    await tester.pumpWidget(const LearnToReadApp());
    expect(find.text('LearnToRead'), findsOneWidget);
  });
}
