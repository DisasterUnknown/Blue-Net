import 'package:bluetooth_chat_app/data/models/message.dart';
import 'package:bluetooth_chat_app/ui/chat_page/widget/message_bubble.dart';
import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/services/mesh_service.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChatPage extends StatefulWidget {
  final String userName;
  final String userId;

  const ChatPage({super.key, required this.userName, required this.userId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _myId;
  Message? _replyTo;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final myId = await AppIdentifier.getId();
    final db = DBHelper();
    final rawMsgs =
        await db.getChatMsgs(widget.userId, myUserCode: myId);
    final loaded = rawMsgs.map((m) {
      final text = (m['msg'] as String?) ?? '';
      final isMe = m['isReceived'] == 0;
      final id = (m['msgId'] as String?) ?? '';
      final sendDateStr = (m['sendDate'] as String?) ??
          DateTime.now().toIso8601String();
      final time = DateTime.tryParse(sendDateStr) ?? DateTime.now();
      return Message(id: id, text: text, isMe: isMe, time: time);
    }).toList();

    if (!mounted) return;
    setState(() {
      _myId = myId;
      _messages.clear();
      _messages.addAll(loaded);
    });
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_myId == null) return;

    String finalText = text;
    String? replyPreview;
    if (_replyTo != null) {
      // Create a simple inline quote.
      final snippet = _replyTo!.text.length > 40
          ? '${_replyTo!.text.substring(0, 40)}…'
          : _replyTo!.text;
      replyPreview = snippet;
      finalText = '$text';
    }

    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    final msg = Message(
      id: localId,
      text: finalText,
      isMe: true,
      time: DateTime.now(),
      replyPreview: replyPreview,
    );

    setState(() {
      _messages.add(msg);
    });

    _controller.clear();
    setState(() {
      _replyTo = null;
    });

    // Persist + enqueue for mesh forwarding.
    MeshService.instance.sendNewMessage(
      myUserCode: _myId!,
      targetUserCode: widget.userId,
      plainText: finalText,
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: const Color(0xFF1F1F1F),
        iconTheme: const IconThemeData(color: Colors.greenAccent),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.greenAccent,
              child: Icon(Icons.person, color: Colors.black),
            ),
            const SizedBox(width: 8),
            Text(widget.userName, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return GestureDetector(
                  onLongPress: () => _onMessageLongPress(msg),
                  child: buildMessageBubble(msg, context),
                );
              },
            ),
          ),
          _buildInputField(),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF1F1F1F),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_replyTo != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.reply,
                          color: Colors.greenAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _replyTo!.text.length > 60
                                ? '${_replyTo!.text.substring(0, 60)}…'
                                : _replyTo!.text,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _replyTo = null;
                            });
                          },
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                  ),
                  minLines: 1,
                  maxLines: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: CircleAvatar(
              backgroundColor: Colors.greenAccent.shade400,
              child: const Icon(Icons.send, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  void _onMessageLongPress(Message msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.white70),
                title: const Text(
                  'Copy',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: msg.text));
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('Message copied')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.white70),
                title: const Text(
                  'Reply',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _replyTo = msg;
                  });
                },
              ),
              if (msg.isMe)
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.white70),
                  title: const Text(
                    'Edit',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _editMessage(msg);
                  },
                ),
              if (msg.isMe)
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteMessage(msg);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editMessage(Message msg) async {
    final controller = TextEditingController(text: msg.text);
    final db = DBHelper();

    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text(
          'Edit Message',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Update your message',
            hintStyle: TextStyle(color: Colors.grey.shade600),
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated == null || updated.isEmpty) return;

    await db.updateChatMsg(widget.userId, msg.id, updated, encrypt: false);

    setState(() {
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx != -1) {
        _messages[idx] = Message(
          id: msg.id,
          text: updated,
          isMe: msg.isMe,
          time: msg.time,
          replyPreview: msg.replyPreview,
        );
      }
    });
  }

  Future<void> _deleteMessage(Message msg) async {
    final db = DBHelper();
    await db.removeChatMsg(widget.userId, msg.id);
    setState(() {
      _messages.removeWhere((m) => m.id == msg.id);
    });
  }
}
