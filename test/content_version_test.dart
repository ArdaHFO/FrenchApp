import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/data/content_version.dart';

void main() {
  test('paketli içerik sürümü ve veritabanı boyutu eşleşir', () {
    final File database = File('assets/db/content.db');
    final String marker =
        File('assets/db/content.version').readAsStringSync().trim();

    expect(marker, kContentVersion);
    expect(database.lengthSync(), kContentLength);
  });
}
