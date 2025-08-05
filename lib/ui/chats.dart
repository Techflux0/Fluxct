import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:intl/intl.dart';
import '../services/auth_services.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final Map<String, dynamic> otherUser;

  const ChatScreen({super.key, required this.chatId, required this.otherUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showEmojiPicker = false;
  Map<String, dynamic>? _replyingTo;
  final ScrollController _scrollController = ScrollController();
  late Stream<DocumentSnapshot> _userStatusStream;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _userStatusStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUser['id'])
        .snapshots();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && _showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
    }
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
      if (_showEmojiPicker) _focusNode.unfocus();
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      await authService.sendMessage(
        chatId: widget.chatId,
        text: text,
        replyTo: _replyingTo?['id'],
      );
      _messageController.clear();
      setState(() => _replyingTo = null);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showMessageOptions(Map<String, dynamic> message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: () {
              setState(() => _replyingTo = message);
              Navigator.pop(context);
            },
          ),
          if (message['senderId'] ==
              Provider.of<AuthService>(context).getCurrentUserId())
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete for everyone'),
              onTap: () => _deleteMessage(message, forEveryone: true),
            ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: message['text']));
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(
    Map<String, dynamic> message, {
    bool forEveryone = false,
  }) async {
    try {
      if (forEveryone) {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .doc(message['id'])
            .delete();
      }
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatLastSeen(Timestamp? lastSeen) {
    if (lastSeen == null) return 'Last seen a long time ago';
    final now = DateTime.now();
    final seen = lastSeen.toDate();
    final diff = now.difference(seen);

    if (diff.inSeconds < 60) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours} hours ago';
    if (diff.inDays == 1) return 'Last seen yesterday';
    return 'Last seen ${DateFormat('MMM d').format(seen)}';
  }

  Widget _buildMessageStatus(Map<String, dynamic> message) {
    if (message['senderId'] !=
        Provider.of<AuthService>(context).getCurrentUserId()) {
      return const SizedBox();
    }

    IconData icon;
    Color color;

    switch (message['status']) {
      case 'sent':
        icon = Icons.check;
        color = Colors.grey;
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = Colors.grey;
        break;
      case 'read':
        icon = Icons.done_all;
        color = Colors.blue;
        break;
      default:
        icon = Icons.access_time;
        color = Colors.grey;
    }

    return Icon(icon, size: 16, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: InkWell(
          onTap: () {
            // Show user profile
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.otherUser['photoUrl'] != null
                    ? NetworkImage(widget.otherUser['photoUrl'])
                    : null,
                child: widget.otherUser['photoUrl'] == null
                    ? Text(widget.otherUser['username'][0].toUpperCase())
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.otherUser['displayName'] ??
                          '@${widget.otherUser['username']}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    StreamBuilder<DocumentSnapshot>(
                      stream: _userStatusStream,
                      builder: (context, snapshot) {
                        final status = snapshot.data?['status'] ?? 'offline';
                        final lastSeen = snapshot.data?['lastSeen'];

                        return Text(
                          status == 'online'
                              ? 'Online'
                              : _formatLastSeen(lastSeen),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: status == 'online'
                                ? Colors.green
                                : Colors.grey,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              // TODO: Implement video call action
            },
          ),
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
              // TODO: Implement call action
            },
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(child: Text('View contact')),
              const PopupMenuItem(child: Text('Media, links, and docs')),
              const PopupMenuItem(child: Text('Search')),
              const PopupMenuItem(child: Text('Mute notifications')),
              const PopupMenuItem(child: Text('Wallpaper')),
              const PopupMenuItem(child: Text('More')),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/ui/bg-chat-tile-dark.png'),
            fit: BoxFit.cover,
            opacity: 0.05,
          ),
        ),
        child: GestureDetector(
          onTap: () {
            if (_showEmojiPicker) {
              setState(() => _showEmojiPicker = false);
            }
          },
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final messages = snapshot.data?.docs ?? [];

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message =
                            messages[index].data() as Map<String, dynamic>;
                        final isMe =
                            message['senderId'] ==
                            authService.getCurrentUserId();
                        final timestamp = message['timestamp']?.toDate();
                        final timeString = timestamp != null
                            ? DateFormat('h:mm a').format(timestamp)
                            : '';

                        final isReplyingTo =
                            _replyingTo != null &&
                            _replyingTo!['id'] == message['id'];

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: isReplyingTo
                              ? BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: Colors.black,
                                      width: 3,
                                    ),
                                  ),
                                )
                              : null,
                          child: GestureDetector(
                            onLongPress: () => _showMessageOptions(message),
                            child: Dismissible(
                              key: Key(message['id']),
                              direction: isMe
                                  ? DismissDirection.endToStart
                                  : DismissDirection.startToEnd,
                              background: Container(
                                color: Colors.blue.withOpacity(0.3),
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: const Icon(
                                  Icons.reply,
                                  color: Colors.blue,
                                ),
                              ),
                              onDismissed: (direction) {
                                setState(() => _replyingTo = message);
                              },
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: isMe
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    children: [
                                      if (!isMe) const SizedBox(width: 8),
                                      Flexible(
                                        child: Container(
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.75,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isMe
                                                ? const Color(0xFFDCF8C6)
                                                : Colors.white,
                                            borderRadius: BorderRadius.only(
                                              topLeft: Radius.circular(
                                                isMe ? 12 : 0,
                                              ),
                                              topRight: Radius.circular(
                                                isMe ? 0 : 12,
                                              ),
                                              bottomLeft: const Radius.circular(
                                                12,
                                              ),
                                              bottomRight:
                                                  const Radius.circular(12),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.grey.withOpacity(
                                                  0.2,
                                                ),
                                                spreadRadius: 1,
                                                blurRadius: 2,
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment: isMe
                                                ? CrossAxisAlignment.end
                                                : CrossAxisAlignment.start,
                                            children: [
                                              if (message['replyTo'] != null)
                                                _buildReplyPreview(message),
                                              Text(
                                                message['text'],
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.black,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    timeString,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Colors.grey,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  _buildMessageStatus(message),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (isMe) const SizedBox(width: 8),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (_replyingTo != null) _buildReplyBar(context, authService),
              if (_showEmojiPicker)
                SizedBox(
                  height: 250,
                  child: EmojiPicker(
                    onEmojiSelected: (category, emoji) {
                      _messageController.text += emoji.emoji;
                    },
                    config: const Config(
                      height: 200,
                      checkPlatformCompatibility: true,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _showEmojiPicker
                            ? Icons.keyboard
                            : Icons.emoji_emotions,
                        color: Colors.grey[600],
                      ),
                      onPressed: _toggleEmojiPicker,
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                focusNode: _focusNode,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _sendMessage(),
                                decoration: const InputDecoration(
                                  hintText: 'Type a message...',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.attach_file),
                              color: Colors.grey[600],
                              onPressed: () {},
                            ),
                            IconButton(
                              icon: const Icon(Icons.camera_alt),
                              color: Colors.grey[600],
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).primaryColor,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview(Map<String, dynamic> message) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(message['replyTo'])
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final reply = snapshot.data!.data() as Map<String, dynamic>;
        final isMe =
            reply['senderId'] ==
            Provider.of<AuthService>(context).getCurrentUserId();

        return Container(
          padding: const EdgeInsets.all(4),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.green[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMe ? 'You' : widget.otherUser['displayName'] ?? 'User',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                reply['text'] ?? '',
                style: TextStyle(fontSize: 10, color: Colors.black),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReplyBar(BuildContext context, AuthService authService) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          Container(width: 4, height: 40, color: Colors.black),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${_replyingTo!['senderId'] == authService.getCurrentUserId() ? 'yourself' : widget.otherUser['displayName'] ?? 'User'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  _replyingTo!['text'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }
}
