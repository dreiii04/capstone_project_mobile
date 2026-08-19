import 'package:capstone_project/models/api_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UTC API timestamps are converted to device local time', () {
    final parsed = parseApiDateTime('2026-08-19T06:28:00.000Z');
    final expected = DateTime.utc(2026, 8, 19, 6, 28).toLocal();

    expect(parsed, expected);
    expect(parsed.isUtc, isFalse);
  });

  test('timezone-free timestamps keep their supplied wall-clock time', () {
    final parsed = parseApiDateTime('2026-08-19T14:28:00');
    expect(parsed, DateTime(2026, 8, 19, 14, 28));
  });
}
