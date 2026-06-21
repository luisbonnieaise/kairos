// Driver do integration_test: recebe os bytes de cada takeScreenshot() e grava
// em build/screenshots/<nome>.png na máquina que roda o `flutter drive`.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final dir = Directory('build/screenshots');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
