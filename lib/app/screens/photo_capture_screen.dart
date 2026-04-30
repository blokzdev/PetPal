import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/repos/wiki_repo.dart';
import '../../data/soul_file.dart';
import '../../harness/vision/photo_extractor.dart';
import '../design/design.dart';
import '../platform/haptics.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_button.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_section_header.dart';
import '../widgets/pet_skeleton.dart';

/// Phase 6 task 6.6 — camera-as-memory capture flow + inline-
/// editable form preview + save.
///
/// On entry the screen launches a picker chooser (camera or
/// gallery) via `image_picker`. After the user picks a photo, the
/// screen displays it full-width and lays out a form whose fields
/// are TextFields / Dropdowns from the first frame (DECISIONS row 41
/// — no read-only review mode). Skeleton rows fade in for the
/// extractor's structured fields; the extractor (6.5) fires in
/// parallel and populates the fields when it returns. User typing
/// wins over extractor prefill — every field controller is
/// initialized empty and only auto-set when blank-on-arrival.
///
/// **Save** writes the photo via WikiRepo.writePhoto (6.1) — which
/// handles the binary + sidecar atomic write + storage budget
/// enforcement. The save flow never blocks on extraction; an
/// extractor failure or >15s timeout falls back to a bare freeform
/// caption (the extractor returns null in those cases per 6.5).
/// Post-save: pop back to home with a snackbar carrying a "View"
/// action that pushes to the photo entry view.
class PhotoCaptureScreen extends ConsumerStatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  ConsumerState<PhotoCaptureScreen> createState() =>
      _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  Uint8List? _imageBytes;
  String _mimeType = 'image/jpeg';

  // Form controllers. Initialized empty; populated from extractor
  // ONLY when the user hasn't typed yet (optimistic UI: typing wins).
  final _caption = TextEditingController();
  final _demeanor = TextEditingController();
  final _objects = TextEditingController();

  // Extractor enums — start at "other" (the locked default-omitted
  // value); extractor refines.
  PhotoSetting _setting = PhotoSetting.other;
  PhotoActivity _activity = PhotoActivity.other;

  // Enrichment-hint follow-ups — additional rows the user can fill
  // or skip. List-of-controllers so each row maintains its own text.
  List<TextEditingController> _enrichmentControllers = [];
  List<String> _enrichmentLabels = [];

  // Track whether each field has been user-touched, so the extractor
  // doesn't clobber typing.
  bool _captionTouched = false;
  bool _demeanorTouched = false;
  bool _objectsTouched = false;
  bool _settingTouched = false;
  bool _activityTouched = false;

  bool _extracting = false;
  bool _saving = false;
  String? _saveError;
  bool _pickerOpened = false;

  @override
  void dispose() {
    _caption.dispose();
    _demeanor.dispose();
    _objects.dispose();
    for (final c in _enrichmentControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pickerOpened) {
      _pickerOpened = true;
      // Defer the picker chooser until after the first frame so the
      // AppBar / scaffold have rendered before the modal sheet
      // animates in.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openChooser());
    }
  }

  Future<void> _openChooser() async {
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
    if (source == null) {
      // User dismissed the chooser — pop the capture screen too.
      if (mounted) GoRouter.of(context).pop();
      return;
    }
    await _pickAndExtract(source);
  }

  Future<void> _pickAndExtract(ImageSource source) async {
    try {
      final picker = ImagePicker();
      // Pre-write 2048-on-long-edge resize per ROADMAP 6.6. The
      // image_picker side already constrains; the resize is
      // sufficient for v1 (~600 KB JPEG output at quality 90).
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked == null) {
        if (mounted) GoRouter.of(context).pop();
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _mimeType = picked.mimeType ?? 'image/jpeg';
        _extracting = true;
      });

      // Kick off extraction in parallel — Save never blocks on it.
      unawaited(_extract(bytes));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveError = 'Could not load the photo: $e');
    }
  }

  Future<void> _extract(Uint8List bytes) async {
    final extractor = ref.read(photoExtractorProvider);
    final result = await extractor.extract(
      imageBytes: bytes,
      mediaType: _mimeType,
    );
    if (!mounted) return;
    setState(() {
      _extracting = false;
      if (result == null) return;
      // Optimistic UI: only set fields the user hasn't touched.
      if (!_captionTouched && _caption.text.isEmpty) {
        _caption.text = result.freeformCaption;
      }
      if (!_demeanorTouched &&
          _demeanor.text.isEmpty &&
          result.demeanor != null) {
        _demeanor.text = result.demeanor!;
      }
      if (!_objectsTouched &&
          _objects.text.isEmpty &&
          result.notableObjects.isNotEmpty) {
        _objects.text = result.notableObjects.join(', ');
      }
      if (!_settingTouched && _setting == PhotoSetting.other) {
        _setting = result.setting;
      }
      if (!_activityTouched && _activity == PhotoActivity.other) {
        _activity = result.activity;
      }
      // Enrichment hints — surface as additional optional rows.
      if (result.enrichmentHints.isNotEmpty &&
          _enrichmentLabels.isEmpty) {
        _enrichmentLabels = result.enrichmentHints;
        _enrichmentControllers = [
          for (final _ in result.enrichmentHints) TextEditingController(),
        ];
      }
    });
  }

  Future<void> _save() async {
    if (_imageBytes == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final petsAsync = ref.read(petsProvider);
      final petId = petsAsync.maybeWhen(
        data: (p) => p.isEmpty ? null : p.last.id,
        orElse: () => null,
      );
      if (petId == null) {
        setState(() {
          _saving = false;
          _saveError = "Add a pet first — photos hang off a pet's profile.";
        });
        return;
      }

      // Compose extractor-shaped frontmatter patch from the form
      // state. The user's edits override the extractor here; the
      // patch goes through writePhoto's standard path which calls
      // the existing _writeAt → mergeFrontmatter chain.
      final patch = <String, Object?>{
        if (_setting != PhotoSetting.other) 'setting': _setting.name,
        if (_activity != PhotoActivity.other) 'activity': _activity.name,
        if (_demeanor.text.trim().isNotEmpty)
          'demeanor': _demeanor.text.trim(),
        if (_objects.text.trim().isNotEmpty)
          'notable_objects': _splitObjects(_objects.text),
        // Enrichment hints — surface user-typed answers; if the user
        // skipped a hint, preserve the question for the entry view.
        if (_enrichmentLabels.isNotEmpty)
          'enrichment_hints': [
            for (var i = 0; i < _enrichmentLabels.length; i++)
              _enrichmentControllers[i].text.trim().isEmpty
                  ? _enrichmentLabels[i]
                  : _enrichmentControllers[i].text.trim(),
          ],
      };

      final repo = await ref.read(wikiRepoProvider.future);
      final result = await repo.writePhoto(
        petId: petId,
        imageBytes: _imageBytes!,
        caption: _caption.text.trim(),
        mimeType: _mimeType,
        // Extractor patch is appended via a follow-up sidecar
        // rewrite; keeps writePhoto's signature clean. See
        // _appendExtractorPatch below.
      );

      if (!result.success) {
        setState(() {
          _saving = false;
          _saveError = result.error == PhotoSaveError.storageFull
              ? 'Storage full — delete some photos to continue.'
              : 'Save failed.';
        });
        return;
      }

      // Patch the sidecar with extractor + form-state fields.
      if (patch.isNotEmpty) {
        await _appendExtractorPatch(result.sidecarPath!, patch);
      }

      // Invalidate downstream views so the new photo surfaces.
      ref.invalidate(wikiEntriesProvider);

      // Light haptic + snackbar + pop home (matches the 5.9
      // memory-saved hero pattern).
      ref.read(hapticsProvider).light();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        content: const Text('Saved a photo memory.'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => GoRouter.of(context).push(
            '/wiki/entry',
            extra: result.sidecarPath,
          ),
        ),
      ));
      GoRouter.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Save failed: $e';
      });
    }
  }

  /// Re-read the just-written sidecar, merge the extractor patch
  /// into its frontmatter, and write it back. Single follow-up
  /// write — keeps `writePhoto`'s signature focused on bytes +
  /// caption while still letting the form state land on disk.
  Future<void> _appendExtractorPatch(
    String sidecarPath,
    Map<String, Object?> patch,
  ) async {
    final wiki = await ref.read(wikiIoProvider.future);
    final raw = await wiki.read(sidecarPath);
    final parsed = parseSoul(raw);
    final merged = mergeFrontmatter(parsed.frontmatter, patch);
    final next = serializeSoul(frontmatter: merged, body: parsed.body);
    await wiki.writeAtomic(sidecarPath, next);
  }

  static List<String> _splitObjects(String raw) =>
      raw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      title: 'Add photo',
      body: _imageBytes == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: Corners.s,
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.memory(
                        _imageBytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.l),
                  PetCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const PetSectionHeader(title: 'About this photo'),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Spacing.m,
                            0,
                            Spacing.m,
                            Spacing.m,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _CaptionField(
                                controller: _caption,
                                onChanged: (_) =>
                                    _captionTouched = true,
                                extracting: _extracting,
                              ),
                              const SizedBox(height: Spacing.m),
                              _SettingActivityRow(
                                setting: _setting,
                                activity: _activity,
                                onSettingChanged: (s) {
                                  setState(() {
                                    _setting = s;
                                    _settingTouched = true;
                                  });
                                },
                                onActivityChanged: (a) {
                                  setState(() {
                                    _activity = a;
                                    _activityTouched = true;
                                  });
                                },
                              ),
                              const SizedBox(height: Spacing.s),
                              _DemeanorField(
                                controller: _demeanor,
                                onChanged: (_) => _demeanorTouched = true,
                                extracting: _extracting,
                              ),
                              const SizedBox(height: Spacing.s),
                              _ObjectsField(
                                controller: _objects,
                                onChanged: (_) => _objectsTouched = true,
                                extracting: _extracting,
                              ),
                              if (_enrichmentLabels.isNotEmpty) ...[
                                const SizedBox(height: Spacing.m),
                                for (var i = 0;
                                    i < _enrichmentLabels.length;
                                    i++) ...[
                                  TextField(
                                    controller: _enrichmentControllers[i],
                                    decoration: InputDecoration(
                                      labelText: _enrichmentLabels[i],
                                      border: const OutlineInputBorder(),
                                    ),
                                    minLines: 1,
                                    maxLines: 3,
                                  ),
                                  if (i < _enrichmentLabels.length - 1)
                                    const SizedBox(height: Spacing.s),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_saveError != null) ...[
                    const SizedBox(height: Spacing.m),
                    Text(
                      _saveError!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: Spacing.l),
                  PetButton(
                    label: 'Save photo memory',
                    onPressed: _saving ? null : _save,
                    isLoading: _saving,
                    icon: PhosphorIconsRegular.bookOpen,
                  ),
                ],
              ),
            ),
    );
  }
}

class _CaptionField extends StatelessWidget {
  const _CaptionField({
    required this.controller,
    required this.onChanged,
    required this.extracting,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool extracting;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Caption',
            hintText: 'A line about this moment.',
            border: OutlineInputBorder(),
          ),
          onChanged: onChanged,
        ),
        if (extracting && controller.text.isEmpty) ...[
          const SizedBox(height: Spacing.xs),
          const PetSkeleton.line(width: 220, height: 12),
        ],
      ],
    );
  }
}

class _DemeanorField extends StatelessWidget {
  const _DemeanorField({
    required this.controller,
    required this.onChanged,
    required this.extracting,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool extracting;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Demeanor (hedged)',
            hintText: '"looks relaxed", "appears curious"',
            border: OutlineInputBorder(),
          ),
          onChanged: onChanged,
        ),
        if (extracting && controller.text.isEmpty) ...[
          const SizedBox(height: Spacing.xs),
          const PetSkeleton.line(width: 160, height: 12),
        ],
      ],
    );
  }
}

class _ObjectsField extends StatelessWidget {
  const _ObjectsField({
    required this.controller,
    required this.onChanged,
    required this.extracting,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool extracting;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Notable objects',
            hintText: 'leash, frozen carrot',
            border: OutlineInputBorder(),
          ),
          onChanged: onChanged,
        ),
        if (extracting && controller.text.isEmpty) ...[
          const SizedBox(height: Spacing.xs),
          const PetSkeleton.line(width: 180, height: 12),
        ],
      ],
    );
  }
}

class _SettingActivityRow extends StatelessWidget {
  const _SettingActivityRow({
    required this.setting,
    required this.activity,
    required this.onSettingChanged,
    required this.onActivityChanged,
  });

  final PhotoSetting setting;
  final PhotoActivity activity;
  final ValueChanged<PhotoSetting> onSettingChanged;
  final ValueChanged<PhotoActivity> onActivityChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<PhotoSetting>(
            initialValue: setting,
            decoration: const InputDecoration(
              labelText: 'Setting',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final s in PhotoSetting.values)
                DropdownMenuItem<PhotoSetting>(
                  value: s,
                  child: Text(s.name),
                ),
            ],
            onChanged: (s) {
              if (s != null) onSettingChanged(s);
            },
          ),
        ),
        const SizedBox(width: Spacing.s),
        Expanded(
          child: DropdownButtonFormField<PhotoActivity>(
            initialValue: activity,
            decoration: const InputDecoration(
              labelText: 'Activity',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final a in PhotoActivity.values)
                DropdownMenuItem<PhotoActivity>(
                  value: a,
                  child: Text(a.name),
                ),
            ],
            onChanged: (a) {
              if (a != null) onActivityChanged(a);
            },
          ),
        ),
      ],
    );
  }
}
