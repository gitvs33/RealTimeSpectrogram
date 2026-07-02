import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(const SpectrogramApp());
    expect(find.text('Real-Time Spectrogram'), findsOneWidget);
  });
}
