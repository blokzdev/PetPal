import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../auth/auth_session_notifier.dart';
import '../chat/chat_error.dart';
import '../chat/chat_notifier.dart';
import '../chat/chat_state.dart';
import '../design/design.dart';
import '../entitlement/entitlement.dart';
import '../entitlement/quota_exception.dart';
import '../providers.dart';
import '../sync/supabase_runtime_config.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/journal_bloom.dart';
import '../widgets/paywall_dispatcher.dart';
import '../widgets/pet_empty_state.dart';
import 'photo_capture_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

/// Phase 7 task F.1 / H.1.c.2 — chat transport gate.
///
/// Two paths satisfy the gate (matches `_selectLlmTransport` in
/// providers.dart):
///   1. **BYOK** — `apiKeyProvider` non-empty → DirectTransport
///      reachable.
///   2. **Signed-in proxy** — auth session + Supabase config
///      populated → ProxyTransport reachable. Per DECISIONS row 75
///      the server-side counter handles quota; the client just
///      needs to know the path is live.
///
/// Anonymous proxy via device-token routes forward to a later
/// commit. Until then, signed-out non-BYOK users see the banner.
bool _chatTransportReady(WidgetRef ref) {
  final keyAsync = ref.watch(apiKeyProvider);
  final hasKey = keyAsync.maybeWhen(
    data: (k) => k != null && k.isNotEmpty,
    orElse: () => false,
  );
  if (hasKey) return true;

  final session = ref.watch(authSessionProvider).value;
  final config = ref.watch(supabaseRuntimeConfigProvider);
  return session != null && config != null;
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
    final hasAttachedImage = ref.read(chatProvider).pendingAttachedImage != null;
    if (text.trim().isEmpty && !hasAttachedImage) return;
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

  /// Phase 6 task 6.9 — composer photo button. Opens the same
  /// camera/gallery chooser sheet shape as 6.6's photo capture flow,
  /// then sets the bytes on `chatProvider.pendingAttachedImage`. The
  /// composer renders a thumbnail strip above the TextField until
  /// send (or × clears).
  Future<void> _pickChatPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(PhosphorIconsRegular.camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.bookOpen),
              title: const Text('Pick from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: Spacing.s),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      ref.read(chatProvider.notifier).attachImage(
            bytes: bytes,
            mediaType: picked.mimeType ?? 'image/jpeg',
          );
    } catch (_) {
      // Best-effort UI; pickers can fail when the OS denies the
      // action. Silent — the user can retry by tapping the button.
    }
  }

  @override
  Widget build(BuildContext context) {
    final petName = ref.watch(petsProvider).maybeWhen(
          data: (pets) => pets.isEmpty ? 'PetPal' : pets.last.name,
          orElse: () => 'PetPal',
        );
    // Phase 6 task 6.2 — chat AppBar avatar reads bytes from the
    // profile-photo provider for the active pet. `petId` is null
    // when no pet exists; falls through to a name-only title.
    final petId = ref.watch(petsProvider).maybeWhen(
          data: (pets) => pets.isEmpty ? null : pets.last.id,
          orElse: () => null,
        );
    final profilePhotoBytes = petId == null
        ? null
        : ref.watch(profilePhotoBytesProvider(petId)).maybeWhen(
              data: (bytes) => bytes,
              orElse: () => null,
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
      titleWidget: profilePhotoBytes == null
          ? null
          : _ChatAppBarTitle(
              avatarBytes: profilePhotoBytes,
              petName: petName,
            ),
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
          // Phase 7 task F.1 — chat is gated on having a working
          // transport. Until Group H wires the proxy + sign-in,
          // chat needs an Anthropic key (= BYOK or auto-migrated
          // pre-Phase-7 key). When neither is present we render a
          // disabled-composer banner pointing at Settings → BYOK
          // toggle so the user has a clear next step.
          if (_chatTransportReady(ref))
            _Composer(
              controller: _input,
              sending: state.sending,
              onSend: _send,
              onAttachPhoto: state.sending ? null : _pickChatPhoto,
              pendingAttachedImage: state.pendingAttachedImage,
              onClearPendingImage: () =>
                  ref.read(chatProvider.notifier).clearAttachedImage(),
            )
          else
            const _ChatUnavailableBanner(),
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
/// works regardless of category.
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
    // Phase 6.6 task 6.6.C.6 — "Keep Chronicling" register on the
    // chat empty heading. Shifts from "describes what the chat IS"
    // ("Chat with PetPal about Loki") to "describes what the user
    // is here to do" ("Keep chronicling Loki"). Aligns with the
    // home greeting body refresh — same active user-verb framing.
    // No-name fallback stays directional ("Tell PetPal about your
    // pet.") since "Keep chronicling your pet" reads awkwardly.
    final heading = hasName
        ? 'Keep chronicling $petName.'
        : 'Tell PetPal about your pet.';
    final body = hasName
        ? "Type what's been happening, or try one of these:"
        : "Type what's been happening, or try one of these:";

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
      icon: PhosphorIconsRegular.chatCircle,
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
          attachedImageBytes: msg.attachedImageBytes,
          attachedImageMediaType: msg.attachedImageMediaType,
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
    this.attachedImageBytes,
    this.attachedImageMediaType,
  });
  final ChatRole role;
  final String text;
  final bool streaming;

  /// Non-null on assistant bubbles produced under a flagged user turn.
  /// Renders the subdued vet-escalation marker per VOICE.md §6 — the
  /// preamble inside [text] is the prominent alert; the badge is the
  /// scrollback marker that survives forever (DECISIONS row 29).
  final String? escalatedCategory;

  /// Phase 6 task 6.9 — bytes of an image the user attached to this
  /// turn. Bubble shows a thumbnail; user bubbles get an inline
  /// "Save as memory" button below the image that routes to
  /// `/photos/capture` with the bytes prefilled (skips the picker).
  final Uint8List? attachedImageBytes;
  final String? attachedImageMediaType;

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
                // Phase 6.6 task 6.6.D.1 — chat scrollback escalation
                // marker uses coral (scheme.tertiary), the systemic
                // medical-attention register per DECISIONS row 64.
                // 'Subdued in stature' lock from CLAUDE.md §10 is
                // preserved by the small icon + small label register
                // — not by muting the color away from coral.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIconsRegular.warningOctagon,
                      size: 14,
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'PetPal flagged this as urgent',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.tertiary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              // Phase 6 task 6.9 — attached photo thumbnail (user
              // bubbles only; assistant turns don't carry images in
              // v1). Tap the "Save as memory" button below to route
              // to /photos/capture with the image prefilled.
              if (attachedImageBytes != null) ...[
                ClipRRect(
                  borderRadius: Corners.s,
                  child: Image.memory(
                    attachedImageBytes!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: Spacing.s),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      GoRouter.of(context).push(
                        '/photos/capture',
                        extra: PhotoCapturePrefill(
                          bytes: attachedImageBytes!,
                          mediaType:
                              attachedImageMediaType ?? 'image/jpeg',
                          captionDraft: text.isEmpty ? null : text,
                        ),
                      );
                    },
                    icon: const Icon(
                      PhosphorIconsRegular.bookOpen,
                      size: 16,
                    ),
                    label: const Text('Save as memory'),
                  ),
                ),
                if (text.isNotEmpty) const SizedBox(height: Spacing.xs),
              ],
              if (text.isNotEmpty)
                Text(
                  text,
                  style: TextStyle(
                    color:
                        isUser ? scheme.onPrimaryContainer : scheme.onSurface,
                    fontStyle:
                        streaming ? FontStyle.italic : FontStyle.normal,
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
    required this.onAttachPhoto,
    required this.pendingAttachedImage,
    required this.onClearPendingImage,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  // Phase 6 task 6.9 — composer photo affordance.
  final VoidCallback? onAttachPhoto;
  final Uint8List? pendingAttachedImage;
  final VoidCallback onClearPendingImage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Task 5.12 — visual lift on the composer. A surfaceContainer
    // slab one tint above the chat thread, hairline divider on top
    // (instead of a hard shadow — keeps the warm palette feeling
    // unforced), Insets.m on horizontal+vertical padding so the
    // touch target lifts off the chat. SafeArea on the bottom so
    // the composer respects gesture-bar insets on Android 10+.
    return Material(
      color: scheme.surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.outlineVariant,
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.m,
                Spacing.s,
                Spacing.m,
                Spacing.s,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pendingAttachedImage != null) ...[
                    _PendingPhotoChip(
                      bytes: pendingAttachedImage!,
                      onClear: onClearPendingImage,
                    ),
                    const SizedBox(height: Spacing.s),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Phase 6 task 6.9 — photo button. Disabled
                      // mid-send to avoid racing the in-flight turn.
                      IconButton(
                        tooltip: 'Attach a photo',
                        onPressed: onAttachPhoto,
                        icon: const Icon(PhosphorIconsRegular.camera),
                      ),
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
                      const SizedBox(width: Spacing.s),
                      IconButton.filled(
                        tooltip: sending ? 'Sending…' : 'Send',
                        onPressed: sending ? null : onSend,
                        icon: sending
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                PhosphorIconsRegular.paperPlaneTilt,
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phase 6 task 6.9 — pending-photo chip in the composer. 56dp
/// thumbnail + a small × that clears the pending attachment. Sits
/// above the TextField so the user sees what they're about to send.
class _PendingPhotoChip extends StatelessWidget {
  const _PendingPhotoChip({required this.bytes, required this.onClear});
  final Uint8List bytes;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: Corners.s,
          child: Image.memory(
            bytes,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox(
              width: 56,
              height: 56,
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            shape: const CircleBorder(),
            elevation: 1,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  PhosphorIconsRegular.x,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ],
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
        return PhosphorIconsRegular.key;
      case ChatErrorCategory.rateLimit:
        return PhosphorIconsRegular.hourglass;
      case ChatErrorCategory.offline:
        return PhosphorIconsRegular.cloudSlash;
      case ChatErrorCategory.server:
        return PhosphorIconsRegular.cloudSlash;
      // Phase 7 task D.1 — quota-exceeded uses the sparkle/upgrade
      // register, not the warning register. The icon hints at "you
      // can keep going by upgrading" — not "something broke."
      case ChatErrorCategory.quotaExceeded:
        return PhosphorIconsRegular.sparkle;
      case ChatErrorCategory.generic:
        return PhosphorIconsRegular.warningCircle;
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
          // Phase 7 task E.1 — quota-exceeded gets the "See Pro
          // options" CTA instead of Retry. Routes via
          // dispatchPaywall so future quota subtypes get routed
          // consistently. The chat error bar is the single
          // chokepoint where the chat surface meets the paywall.
          if (error.category == ChatErrorCategory.quotaExceeded) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => dispatchPaywall(
                context,
                TextQuotaExceeded(Entitlement.freeAnonymous()),
              ),
              child: const Text('See Pro options'),
            ),
          ] else if (canRetry &&
              error.category != ChatErrorCategory.auth) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}


/// Phase 6 task 6.2 — chat AppBar title with the pet's profile
/// photo as a small circular avatar to the left of the name. Used
/// as the AppScaffold `titleWidget:` slot when the active pet has
/// a profile photo set; falls through to a plain text title
/// otherwise (no avatar = no leading gap).
class _ChatAppBarTitle extends StatelessWidget {
  const _ChatAppBarTitle({
    required this.avatarBytes,
    required this.petName,
  });

  final Uint8List avatarBytes;
  final String petName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipOval(
          child: Image.memory(
            avatarBytes,
            width: 28,
            height: 28,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            // Stale / corrupt avatar bytes fall through to a sage
            // pawprint placeholder so the AppBar never empty-renders.
            errorBuilder: (ctx, _, _) => Icon(
              PhosphorIconsRegular.pawPrint,
              size: 18,
              color: Theme.of(ctx).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: Spacing.s),
        Flexible(
          child: Text(
            petName,
            overflow: TextOverflow.ellipsis,
            style: theme.appBarTheme.titleTextStyle ??
                theme.textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

/// Phase 7 task F.1 / H.1.c.2 — chat-unavailable banner.
///
/// Renders in place of [_Composer] when no transport is reachable
/// (per `_chatTransportReady`). Two CTAs map onto the two real
/// paths: sign-in routes to /sign-in and unlocks the proxy lane;
/// "Use your own key" routes to Settings to flip the BYOK toggle.
/// Sage register only; uses the surfaceContainer slab +
/// outlineVariant divider so the chrome doesn't jump when chat
/// becomes reachable and the composer slides back in.
class _ChatUnavailableBanner extends ConsumerWidget {
  const _ChatUnavailableBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasSupabase =
        ref.watch(supabaseRuntimeConfigProvider) != null;

    return Material(
      color: scheme.surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.outlineVariant,
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.m,
                Spacing.m,
                Spacing.m,
                Spacing.m,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        PhosphorIconsRegular.key,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: Spacing.s),
                      Expanded(
                        child: Text(
                          hasSupabase
                              ? "Chat needs a connection to Claude. Sign "
                                  "in for the free monthly allowance, or "
                                  "use your own Anthropic key in Settings."
                              : "Chat needs a connection to Claude. Add "
                                  "your Anthropic key in Settings to start "
                                  "chatting.",
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.85),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.s),
                  if (hasSupabase) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () =>
                              GoRouter.of(context).push('/settings'),
                          icon: const Icon(
                            PhosphorIconsRegular.key,
                            size: 16,
                          ),
                          label: const Text('Use your own key'),
                        ),
                        const SizedBox(width: Spacing.xs),
                        FilledButton.icon(
                          onPressed: () =>
                              GoRouter.of(context).push('/sign-in'),
                          icon: const Icon(
                            PhosphorIconsRegular.signIn,
                            size: 16,
                          ),
                          label: const Text('Sign in'),
                        ),
                      ],
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () =>
                            GoRouter.of(context).push('/settings'),
                        icon:
                            const Icon(PhosphorIconsRegular.gear, size: 16),
                        label: const Text('Open Settings'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
