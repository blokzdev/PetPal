import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_notifier.dart';
import '../chat/chat_state.dart';
import '../providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(chatProvider.notifier).send(text);
    // Defer scroll until the new message has rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final petName = ref.watch(petsProvider).maybeWhen(
          data: (pets) => pets.isEmpty ? 'PetPal' : pets.last.name,
          orElse: () => 'PetPal',
        );
    final state = ref.watch(chatProvider);

    // Auto-scroll on streaming deltas too — chat feels glitchy otherwise.
    ref.listen(chatProvider, (prev, next) {
      if ((prev?.streamingAssistant ?? '') != (next.streamingAssistant ?? '')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(petName)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: state.messages.isEmpty &&
                      state.streamingAssistant == null
                  ? const _EmptyChat()
                  : _MessageList(
                      controller: _scrollController,
                      state: state,
                    ),
            ),
            if (state.error != null) _ErrorBanner(message: state.error!),
            _Composer(
              controller: _input,
              sending: state.sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 56, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'Tell PetPal something about your pet to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.controller, required this.state});
  final ScrollController controller;
  final ChatState state;

  @override
  Widget build(BuildContext context) {
    final draft = state.streamingAssistant;
    final hasDraft = draft != null;
    final total = state.messages.length + (hasDraft ? 1 : 0);
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: total,
      itemBuilder: (context, i) {
        if (hasDraft && i == total - 1) {
          return _Bubble(
            role: ChatRole.assistant,
            text: draft.isEmpty ? '…' : draft,
            streaming: true,
          );
        }
        final msg = state.messages[i];
        return _Bubble(role: msg.role, text: msg.text);
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.role,
    required this.text,
    this.streaming = false,
  });
  final ChatRole role;
  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:
                isUser ? scheme.primaryContainer : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: isUser ? scheme.onPrimaryContainer : scheme.onSurface,
              fontStyle: streaming ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              enabled: !sending,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: 'Tell PetPal what happened…',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => sending ? null : onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}
