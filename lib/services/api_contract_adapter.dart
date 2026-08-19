import 'package:capstone_project/models/document_catalog.dart';

Map<String, dynamic>? apiObject(
  Map<String, dynamic> data, {
  String? key,
}) {
  final nested = key == null ? null : data[key];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  if (data.isEmpty || data.containsKey('items')) return null;
  return Map<String, dynamic>.from(data);
}

List<Map<String, dynamic>> apiList(
  Map<String, dynamic> data, {
  required String key,
}) {
  final raw = data[key] ?? data['items'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String _text(dynamic value) => value?.toString().trim() ?? '';

Map<String, dynamic> normalizeProfileRecord(Map<String, dynamic> source) {
  final record = Map<String, dynamic>.from(source);
  final role = _text(record['role']).toLowerCase();
  final email = _text(record['email']);
  final isStudent = role == 'student' || role == 'current_student';

  record['id'] = _text(record['id']).isNotEmpty ? record['id'] : record['_id'];
  record['program'] = _text(record['program']).isNotEmpty
      ? record['program']
      : record['course'];
  record['profileImageUrl'] = _text(record['profileImageUrl']).isNotEmpty
      ? record['profileImageUrl']
      : record['profilePic'];
  if (isStudent) {
    record['schoolEmail'] =
        _text(record['schoolEmail']).isNotEmpty ? record['schoolEmail'] : email;
    record['personalEmail'] = _text(record['personalEmail']);
  } else {
    record['personalEmail'] = _text(record['personalEmail']).isNotEmpty
        ? record['personalEmail']
        : email;
    record['schoolEmail'] = _text(record['schoolEmail']);
  }
  return record;
}

Map<String, dynamic> normalizeRequestRecord(Map<String, dynamic> source) {
  final record = Map<String, dynamic>.from(source);
  record['id'] = _text(record['id']).isNotEmpty ? record['id'] : record['_id'];
  record['docName'] = _text(record['docName']).isNotEmpty
      ? record['docName']
      : record['documentType'];
  record['createdAt'] = _text(record['createdAt']).isNotEmpty
      ? record['createdAt']
      : record['dateRequested'];
  final catalogPrice = documentPriceForName(_text(record['docName']));
  final storedPrice = _amount(record['documentPrice']);
  final documentPrice =
      storedPrice > 0 || catalogPrice == 0 ? storedPrice : catalogPrice;
  final processingFee = _amount(record['processingFee']);
  final storedTotal = _amount(record['totalAmount']);
  final fallbackTotal = documentPrice + processingFee;
  record['documentPrice'] = documentPrice;
  record['processingFee'] = processingFee;
  record['totalAmount'] =
      storedTotal > 0 || fallbackTotal == 0 ? storedTotal : fallbackTotal;
  return record;
}

double _amount(dynamic value) {
  if (value is num) return value.isFinite && value >= 0 ? value.toDouble() : 0;
  final parsed = double.tryParse(value?.toString().trim() ?? '');
  return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : 0;
}

Map<String, dynamic> normalizeTransactionRecord(Map<String, dynamic> source) {
  final record = Map<String, dynamic>.from(source);
  record['id'] = _text(record['id']).isNotEmpty ? record['id'] : record['_id'];
  record['docName'] = _text(record['docName']).isNotEmpty
      ? record['docName']
      : record['documentType'];
  record['createdAt'] = _text(record['createdAt']).isNotEmpty
      ? record['createdAt']
      : record['date'];
  record['paymentType'] = _text(record['paymentType']).isNotEmpty
      ? record['paymentType']
      : record['paymentMode'];
  record['totalAmount'] = record['totalAmount'] ?? record['amount'];
  return record;
}

Map<String, dynamic> normalizeNotificationRecord(Map<String, dynamic> source) {
  final record = Map<String, dynamic>.from(source);
  record['id'] = _text(record['id']).isNotEmpty ? record['id'] : record['_id'];
  record['createdAt'] = _text(record['createdAt']).isNotEmpty
      ? record['createdAt']
      : record['date'];
  if (_text(record['title']).isEmpty) record['title'] = 'Notification';
  return record;
}
