import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_app/main.dart';
import 'package:flutter_app/services/spectrogram_service.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SpectrogramService(),
        child: const SpectrogramApp(),
      ),
    );
    // The app title is "Once".
    expect(find.text('Once'), findsOneWidget);
  });
}
