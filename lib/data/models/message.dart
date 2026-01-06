class Message {
  final String id;
  final bool isMe;
  final DateTime time;
  final String? replyPreview;
  String text;

  Message({
    required this.id,
    required this.text,
    required this.isMe,
    required this.time,
    this.replyPreview,
  });
}
