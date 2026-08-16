class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.createdAt,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String message;
  final String timestamp;
  final DateTime createdAt;
  bool isRead;
}
