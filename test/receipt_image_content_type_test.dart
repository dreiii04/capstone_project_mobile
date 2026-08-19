import 'dart:typed_data';

import 'package:capstone_project/services/mongo_data_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receipt uploads declare MIME type from verified image bytes', () {
    final jpeg = receiptImageContentType(
      Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
    );
    final png = receiptImageContentType(
      Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
    );

    expect(jpeg?.mimeType, 'image/jpeg');
    expect(png?.mimeType, 'image/png');
    expect(receiptImageContentType(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
