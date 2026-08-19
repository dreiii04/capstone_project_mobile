DateTime? tryParseApiDateTime(dynamic value) {
  if (value is DateTime) return value.isUtc ? value.toLocal() : value;
  if (value is String) {
    final parsed = DateTime.tryParse(value.trim());
    if (parsed != null) return parsed.isUtc ? parsed.toLocal() : parsed;
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
  }
  return null;
}

DateTime parseApiDateTime(dynamic value, {DateTime? fallback}) {
  return tryParseApiDateTime(value) ?? fallback ?? DateTime.now();
}
