import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_error.dart';
import '../chat/chat_notifier.dart';
import '../chat/chat_state.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/journal_bloom.dart';
import '../widgets/pet_empty_state.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();

  /// Monotonic id of the bloom currently mounted, or null if no bloom
  /// is visible. Drives the Stack overlay; bumps on each successful
  /// `write_wiki_entry` so back-to-back saves restart the animation
  /// rather than ignoring later events. The bloom widget itself is
  /// keyed on this id so a fresh AnimationController instantiates
  /// each time. (Task 5.9 — bubble→journal bloom hero.)
  int? _activeBloomId;

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Fire the 5.9 hero choreography — bubble→journal bloom + snackbar.
  /// Called from `ref.listen` when `recentMemorySave?.id` increments.
  void _runMemorySavedHero(MemorySavedEvent event, String petName) {
    setState(() => _activeBloomId = event.id);
    final hasName = petName.isNotEmpty && petName != 'PetPal';
    final message = hasName
        ? "Saved to $petName's journal"
        : "Saved to your pet's journal";
    appSnackBar(
      context,
      message,
      action: SnackBarAction(
        label: 'View',
        onPressed: () => GoRouter.of(context).push(
          '/wiki/entry',
          extra: event.path,
        ),
      ),
    );
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
      // Task 5.9 — fire the memory-saved hero on transitions of
      // `recentMemorySave?.id`. The chat notifier increments the id
      // on every successful write_wiki_entry, so back-to-back saves
      // each get their own bloom + snackbar.
      final prevId = prev?.recentMemorySave?.id ?? 0;
      final nextEvent = next.recentMemorySave;
      if (nextEvent != null && nextEvent.id > prevId) {
        _runMemorySavedHero(nextEvent, petName);
      }
    });

    final ui = state.uiMessages.toList();
    final messagePane = ui.isEmpty && state.streamingAssistant == null
        ? EmptyChatForTesting(
            petName: petName,
            onSuggest: (prompt) {
              _input.text = prompt;
              _input.selection = TextSelection.fromPosition(
                TextPosition(offset: _input.text.length),
              );
            },
          )
        : _MessageList(
            controller: _scrollController,
            messages: ui,
            streamingAssistant: state.streamingAssistant,
            streamingEscalation: state.streamingEscalation,
          );
    return AppScaffold(
      title: petName,
      body: Column(
        children: [
          Expanded(
            // Stack the message list and the bloom overlay. The bloom
            // sits Bottom-Center, ~56dp above the bottom edge so it
            // appears to rise from the most-recent assistant bubble's
            // top edge (typical bubble height) rather than from the
            // composer.
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                messagePane,
                if (_activeBloomId != null)
                  Positioned(
                    bottom: 56,
                    child: JournalBloom(
                      key: ValueKey('bloom-$_activeBloomId'),
                      onComplete: () {
                        if (mounted) {
                          setState(() => _activeBloomId = null);
                        }
                      },
                    ),
                  ),
              ],
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
    );
  }
}

/// Chat empty state — task 5.7 (locked option: suggested prompts as
/// tappable chips). The user has just opened chat with their pet's
/// agent and has no mental model for what to type. Three concrete
/// prompt chips lower activation energy; tapping a chip pre-fills
/// the composer (does NOT auto-send — user can still edit).
///
/// Per VOICE.md §1: warm, never saccharine, no anthropomorphizing
/// PetPal. The heading describes what the chat IS ("Chat with PetPal
/// about Loki"), not a greeting. The chips are concrete things an
/// owner might actually say, not chatbot-demo prompts.
///
/// Per VOICE.md §5 the heading interpolates the pet name. The third
/// chip stays generic where pet name doesn't naturally fit, so it
/// works regardless of species.
class EmptyChatForTesting extends StatelessWidget {
  const EmptyChatForTesting({
    super.key,
    required this.petName,
    required this.onSuggest,
  });
  final String petName;
  final ValueChanged<String> onSuggest;

  @override
  Widget build(BuildContext context) {
    final hasName = petName.isNotEmpty && petName != 'PetPal';
    final heading = hasName
        ? 'Chat with PetPal about $petName.'
        : 'Chat with PetPal about your pet.';
    final body = hasName
        ? "Try one of these, or just type what's been happening:"
        : "Try one of these, or just type what's been happening:";

    final prompts = hasName
        ? <String>[
            '$petName had vaccines today',
            '$petName has been scratching since yesterday',
            'What food works for $petName?',
          ]
        : const <String>[
            'My pet had vaccines today',
            'My pet has been scratching since yesterday',
            'What food should I avoid?',
          ];

    return PetEmptyState(
      icon: Icons.chat_bubble_outline,
      heading: heading,
      body: body,
      action: Wrap(
        spacing: Spacing.s,
        runSpacing: Spacing.s,
        alignment: WrapAlignment.center,
        children: [
          for (final prompt in prompts)
            ActionChip(
              label: Text(prompt),
              onPressed: () => onSuggest(prompt),
            ),
        ],
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
