import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openpelo/providers/app_provider.dart';
import 'package:openpelo/theme/app_theme.dart';
import 'package:openpelo/widgets/file_manager_dialog.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(360, 800)]) {
    testWidgets('file manager fits at phone size $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = AppProvider();
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: FileManagerDialog(deviceSerial: 'demo')),
          ),
        ),
      );
      // No pumpAndSettle: while the (unreachable) test device loads, the
      // dialog shows an indeterminate progress indicator by design.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The toolbar gives the shortcut chips their own row at phone widths
      // instead of squeezing the path field; all four stay visible.
      expect(find.text('sdcard'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('DCIM'), findsOneWidget);
      expect(find.text('Movies'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
