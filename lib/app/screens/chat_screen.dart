import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_error.dart';
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

    final ui = state.uiMessages.toList();
    return Scaffold(
      appBar: AppBar(title: Text(petName)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ui.isEmpty && state.streamingAssistant == null
                  ? _EmptyChat(petName: petName)
                  : _MessageList(
                      controller: _scrollController,
                      messages: ui,
                      streamingAssistant: state.streamingAssistant,
                      streamingEscalation: state.streamingEscalation,
                    ),
            ),
            if (state.activeTools.isNotEmpty)
              _ToolPills(pills: state.activeTools, petName: petName),
            if (state.error != null)
              _ErrorBanner(
                error: state.error!,
                canRetry: !state.sending && state.lastFailedInput != null,
                onRetry: () => ref.read(chatProvider.notifier).retry(),
              ),
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
  const _EmptyChat({required this.petName});
  final String petName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = petName == 'PetPal'
        ? 'Tell PetPal something about your pet to get started.'
        : "Tell PetPal what's been happening with $petName.";
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 56, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              body,
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
  const _MessageList({
    required this.controller,
    required this.messages,
    required this.streamingAssistant,
    required this.streamingEscalation,
  });
  final ScrollController controller;
  final List<ChatMessage> messages;
  final String? streamingAssistant;
  final String? streamingEscalation;

  @override
  Widget build(BuildContext context) {
    final draft = streamingAssistant;
    final hasDraft = draft != null;
    final total = messages.length + (hasDraft ? 1 : 0);
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
            escalatedCategory: streamingEscalation,
          );
        }
        final msg = messages[i];
        return _Bubble(
          role: msg.role,
          text: msg.text,
          escalatedCategory: msg.escalatedCategory,
        );
      },
    );
  }
}

class _ToolPills extends StatelessWidget {
  const _ToolPills({required this.pills, required this.petName});
  final List<ToolPill> pills;
  final String petName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final pill in pills)
            Chip(
              avatar: const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              label: Text('${_humanizeToolName(pill.name, petName)}…'),
              labelStyle: TextStyle(color: scheme.onSurfaceVariant),
              backgroundColor: scheme.surfaceContainerHigh,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
        ],
      ),
    );
  }
}

/// User-facing translation of harness tool names (VOICE.md §3 table).
/// The user must never see raw `read_wiki` etc. on a pill.
String _humanizeToolName(String name, String petName) {
  final hasName = petName.isNotEmpty && petName != 'PetPal';
  switch (name) {
    case 'read_wiki':
      return hasName ? "checking $petName's journal" : 'checking the journal';
    case 'search_wiki':
      return hasName ? "searching $petName's journal" : 'searching the journal';
    case 'write_wiki_entry':
      return 'saving a memory';
    case 'update_soul':
      return hasName ? "updating $petName's profile" : 'updating the profile';
    case 'schedule_reminder':
      return 'setting a reminder';
    case 'log_weight':
      return hasName ? "logging $petName's weight" : 'logging weight';
    case 'list_reminders':
      return 'checking reminders';
    case 'red_flag_check':
      return 'checking for red flags';
    case 'load_skill':
      return 'loading a care guide';
    default:
      return 'thinking';
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.role,
    required this.text,
    this.streaming = false,
    this.escalatedCategory,
  });
  final ChatRole role;
  final String text;
  final bool streaming;

  /// Non-null on assistant bubbles produced under a flagged user turn.
  /// Renders the subdued vet-escalation marker per VOICE.md §6 — the
  /// preamble inside [text] is the prominent alert; the badge is the
  /// scrollback marker that survives forever (DECISIONS row 29).
  final String? escalatedCategory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = role == ChatRole.user;
    final isFlagged = !isUser && escalatedCategory != null;
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isFlagged) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'PetPal flagged this as urgent',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Text(
                text,
                style: TextStyle(
                  color: isUser ? scheme.onPrimaryContainer : scheme.onSurface,
                  fontStyle: streaming ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
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
  const _ErrorBanner({
    required this.error,
    required this.canRetry,
    required this.onRetry,
  });
  final ChatError error;
  final bool canRetry;
  final VoidCallback onRetry;

  IconData _iconFor(ChatErrorCategory c) {
    switch (c) {
      case ChatErrorCategory.auth:
        return Icons.key_off;
      case ChatErrorCategory.rateLimit:
        return Icons.hourglass_empty;
      case ChatErrorCategory.offline:
        return Icons.signal_wifi_off;
      case ChatErrorCategory.server:
        return Icons.cloud_off;
      case ChatErrorCategory.generic:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconFor(error.category), color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error.message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          if (canRetry &&
              error.category != ChatErrorCategory.auth) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}
