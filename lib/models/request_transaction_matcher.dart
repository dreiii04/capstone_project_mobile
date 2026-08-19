import 'api_date_time.dart';

String _normalized(dynamic value) {
  return value
          ?.toString()
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[\s-]+'), '_') ??
      '';
}

String _firstText(Map<String, dynamic> record, List<String> keys) {
  for (final key in keys) {
    final value = record[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}

Set<String> _requestIdentifiers(Map<String, dynamic> request) {
  return {
    _normalized(request['requestId']),
    _normalized(request['linkedRequestId']),
    _normalized(request['documentRequestId']),
    _normalized(request['id']),
    _normalized(request['_id']),
  }..remove('');
}

String _transactionRequestId(Map<String, dynamic> transaction) {
  return _normalized(
    _firstText(
      transaction,
      const ['requestId', 'linkedRequestId', 'documentRequestId'],
    ),
  );
}

bool requestMatchesTransaction(
  Map<String, dynamic> request,
  Map<String, dynamic> transaction, {
  Duration legacyMatchWindow = const Duration(minutes: 5),
}) {
  final requestIds = _requestIdentifiers(request);
  final transactionRequestId = _transactionRequestId(transaction);

  // Once either side has a stable request ID, details such as document type,
  // purpose, or a changed display name must never override an ID mismatch.
  if (requestIds.isNotEmpty) {
    return transactionRequestId.isNotEmpty &&
        requestIds.contains(transactionRequestId);
  }
  if (transactionRequestId.isNotEmpty) return false;

  final requestDocument = _normalized(request['docName']);
  final transactionDocument = _normalized(transaction['docName']);
  final requestPurpose = _normalized(request['purpose']);
  final transactionPurpose = _normalized(transaction['purpose']);
  if (requestDocument.isEmpty ||
      requestDocument != transactionDocument ||
      requestPurpose != transactionPurpose) {
    return false;
  }

  final requestedAt = tryParseApiDateTime(request['createdAt']);
  final paidAt = tryParseApiDateTime(transaction['createdAt']);
  if (requestedAt == null || paidAt == null) return false;
  return paidAt.difference(requestedAt).abs() <= legacyMatchWindow;
}
