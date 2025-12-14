import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:movie/app/modules/season_view/bindings/season_view_binding.dart';
import 'package:movie/app/modules/season_view/views/season_view_view.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:ui';
import 'package:video_player/video_player.dart';

import '../../../model/subject_list.dart';
import '../controllers/subject_detail_controller.dart';

// --- UI Constants ---
const Color kBackgroundColor = Color(0xFF101010);
const Color kPrimaryColor = Colors.white;
const Color kSecondaryTextColor = Colors.white70;
const Color kAccentColor = Color(0xFF8A2BE2);
const Color kSurfaceColor = Color(0xFF1A1A1A);

class SubjectDetailView extends GetView<SubjectDetailController> {
  const SubjectDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Scaffold(
        backgroundColor: kBackgroundColor,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: controller.isLoading.value
              ? const Center(
            key: ValueKey('loader'),
            child: CircularProgressIndicator(color: kAccentColor),
          )
              : Stack(
            key: const ValueKey('content'),
            children: [
              _BackgroundImageAndGradient(
                  subject: controller.subject.value),
              const _DetailContent(),
              const _TopBackButton(),
            ],
          ),
        ),
      );
    });
  }
}

// MARK: - Sub-Widgets

class _BackgroundImageAndGradient extends GetView<SubjectDetailController> {
  final Subject? subject;
  const _BackgroundImageAndGradient({this.subject, super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Get.width < 600;
    final imageUrl = subject?.cover?.url;

    return Obx(() {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Shimmer.fromColors(
                  baseColor: Colors.grey[850]!,
                  highlightColor: Colors.grey[800]!,
                  child: Container(color: Colors.black),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[900],
                ),
              ),
            ),
          if (controller.videoPlayerController.value?.value.isInitialized ??
              false)
            AnimatedOpacity(
              opacity: controller.showTrailer.value ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 1000),
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller
                        .videoPlayerController.value!.value.size.width,
                    height: controller
                        .videoPlayerController.value!.value.size.height,
                    child: VideoPlayer(controller.videoPlayerController.value!),
                  ),
                ),
              ),
            ),
          if (!isMobile)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kBackgroundColor,
                    kBackgroundColor.withOpacity(0.7),
                    Colors.transparent,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.center,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  kBackgroundColor,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: isMobile ? const [0.3, 1.0] : const [0.0, 1.0],
              ),
            ),
          ),
        ],
      );
    });
  }
}

// MODIFIED: Converted to a stateless GetView for better reactivity.
class _DetailContent extends GetView<SubjectDetailController> {
  const _DetailContent({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Get.width < 600;

    return Obx(() {
      return AnimatedSlide(
        offset: controller.isContentLoaded.value
            ? Offset.zero
            : const Offset(0, 0.1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: controller.isContentLoaded.value ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Align(
            alignment: isMobile ? Alignment.bottomLeft : Alignment.centerLeft,
            child: SingleChildScrollView(
              padding: isMobile
                  ? const EdgeInsets.fromLTRB(24, 100, 24, 40)
                  : const EdgeInsets.fromLTRB(60, 60, 60, 40),
              child: SizedBox(
                width: isMobile ? double.infinity : Get.width * 0.45,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- Genre, Title, Metadata ---
                    Text(
                      (controller.subject.value?.genre ?? '').toUpperCase(),
                      style: const TextStyle(
                        color: kAccentColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      controller.subject.value?.title ?? 'No Title',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: kPrimaryColor,
                        fontSize: isMobile ? 40 : 52,
                        fontFamily: 'Bebas Neue',
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MetadataRow(
                      releaseDate:
                      controller.subject.value?.releaseDate ?? '',
                      country: controller.subject.value?.countryName ?? '',
                      duration: controller.subject.value?.duration ?? 0,
                    ),
                    const SizedBox(height: 24),

                    // --- Description ---
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: kSurfaceColor.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            controller.subject.value?.description ??
                                'No description available.',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kSecondaryTextColor,
                                fontSize: 16,
                                height: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // --- Action Buttons ---
                    Obx(() {
                      final List<Widget> actionButtons = [];
                      final subject = controller.subject.value;
                      final resource = controller.resource.value;

                      if (controller.hasSavedProgress.value) {
                        actionButtons.add(
                          _ActionButton(
                            focusNode: controller.playButtonFocusNode,
                            icon: Icons.play_circle_outline,
                            label:
                            'Continue S${controller.lastPlayedSeason.value} E${controller.lastPlayedEpisode.value}',
                            onPressed: controller.continuePlayback,
                            isPrimary: true,
                          ),
                        );
                      } else if (resource != null &&
                          (resource.seasons?.isNotEmpty ?? false)) {
                        actionButtons.add(
                          _ActionButton(
                            focusNode: controller.playButtonFocusNode,
                            icon: Icons.play_arrow_rounded,
                            label: resource.seasons!.first.se == 0
                                ? 'Play'
                                : 'Play S${resource.seasons!.first.se} E1',
                            onPressed: controller.playFromBeginning,
                            isPrimary: true,
                          ),
                        );
                      }

                      if (resource != null &&
                          (resource.seasons?.isNotEmpty ?? false) &&
                          resource.seasons!.first.se != 0) {
                        actionButtons.add(
                          _ActionButton(
                            icon: Icons.video_library_outlined,
                            label: 'More Episodes',
                            onPressed: () {
                              Get.to(() => const SeasonView(),
                                  binding: SeasonViewBinding(),
                                  arguments: [subject, resource]);
                            },
                          ),
                        );
                      }

                      if (controller.hasSavedProgress.value) {
                        actionButtons.add(
                          _ActionButton(
                            icon: Icons.replay,
                            label: 'Play from Beginning',
                            onPressed: controller.playFromBeginning,
                          ),
                        );
                      }

                      actionButtons.add(
                        _ActionButton(
                          icon: Icons.language,
                          label: 'Language',
                          subtitle: subject?.title,
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return Obx(() =>
                                controller.subjectsList.isNotEmpty
                                    ? _LanguageSelectionDialog(
                                  subjects: controller.subjectsList,
                                  onLanguageSelected:
                                      (selectedSubject) {
                                    if (selectedSubject.subjectId !=
                                        null) {
                                      controller.fetchSubjectDetails(
                                          selectedSubject
                                              .subjectId!);
                                    }
                                  },
                                )
                                    : const SizedBox());
                              },
                            );
                          },
                        ),
                      );

                      return Wrap(
                        spacing: 16.0,
                        runSpacing: 16.0,
                        children: actionButtons,
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _MetadataRow extends StatelessWidget {
  final String releaseDate;
  final String country;
  final int duration;

  const _MetadataRow({
    required this.releaseDate,
    required this.country,
    required this.duration,
  });

  String formatDuration(int seconds) {
    if (seconds == 0) return '';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    String result = '';
    if (hours > 0) result += '${hours}h ';
    if (minutes > 0) result += '${minutes}m';
    return result.trim();
  }

  @override
  Widget build(BuildContext context) {
    final String year = (releaseDate.isNotEmpty && releaseDate.length >= 4)
        ? releaseDate.substring(0, 4)
        : '';

    final List<String> items = [
      year,
      country,
      formatDuration(duration),
    ]..removeWhere((s) => s.isEmpty);

    if (items.isEmpty) return const SizedBox.shrink();

    return Row(
      children: items
          .map((item) => Text(item,
          style: const TextStyle(
              color: kSecondaryTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w500)))
          .expand((widget) => [
        widget,
        if (widget.data != items.last)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.0),
            child: Text('•',
                style: TextStyle(
                    color: kSecondaryTextColor, fontSize: 14)),
          ),
      ])
          .toList(),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onPressed;
  final bool isPrimary;
  final FocusNode? focusNode;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onPressed,
    this.isPrimary = false,
    this.focusNode,
  });

  @override
  State<_ActionButton> createState() => __ActionButtonState();
}

class __ActionButtonState extends State<_ActionButton> {
  bool _isFocused = false;
  late final FocusNode _focusNode;
  bool _isInternalNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _focusNode = FocusNode();
      _isInternalNode = true;
    } else {
      _focusNode = widget.focusNode!;
    }
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_isInternalNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
    widget.isPrimary ? kPrimaryColor : kSurfaceColor.withOpacity(0.6);
    final contentColor = widget.isPrimary ? kBackgroundColor : kPrimaryColor;

    return Focus(
      focusNode: _focusNode,
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: BorderRadius.circular(30),
        child: AnimatedScale(
          scale: _isFocused ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(30),
              border: widget.isPrimary
                  ? Border.all(color: kAccentColor, width: 1.5)
                  : _isFocused
                  ? Border.all(color: kAccentColor, width: 1.5)
                  : null,
              boxShadow: [
                if (_isFocused)
                  BoxShadow(
                    color: (widget.isPrimary ? kPrimaryColor : kAccentColor)
                        .withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: contentColor),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: contentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (widget.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          widget.subtitle!,
                          style: TextStyle(
                            color: contentColor.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBackButton extends StatefulWidget {
  const _TopBackButton();

  @override
  State<_TopBackButton> createState() => _TopBackButtonState();
}

class _TopBackButtonState extends State<_TopBackButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = Get.width < 600;
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: isMobile ? topPadding + 16 : 40,
      left: isMobile ? 16 : 40,
      child: Focus(
        onFocusChange: (hasFocus) => setState(() => _isFocused = hasFocus),
        child: InkWell(
          onTap: () => Get.back(),
          borderRadius: BorderRadius.circular(50),
          child: AnimatedScale(
            scale: _isFocused ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kSurfaceColor.withOpacity(0.5),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isFocused ? kPrimaryColor : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: kPrimaryColor, size: 28),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageSelectionDialog extends StatelessWidget {
  final List<Subject> subjects;
  final Function(Subject) onLanguageSelected;

  const _LanguageSelectionDialog(
      {required this.subjects, required this.onLanguageSelected});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: AlertDialog(
        backgroundColor: kSurfaceColor.withOpacity(0.85),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        title: const Text(
          'Select Audio & Subtitles',
          style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: subjects.isEmpty
              ? const Center(
              child: Text("No other languages found.",
                  style: TextStyle(color: kSecondaryTextColor)))
              : ListView.separated(
            shrinkWrap: true,
            itemCount: subjects.length,
            separatorBuilder: (context, index) => Divider(
              color: Colors.white.withOpacity(0.1),
            ),
            itemBuilder: (context, index) {
              final subject = subjects[index];
              return ListTile(
                title: Text(
                  subject.title ?? 'No Title',
                  style: const TextStyle(color: kSecondaryTextColor),
                ),
                onTap: () {
                  onLanguageSelected(subject);
                  Navigator.of(context).pop();
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                hoverColor: kAccentColor.withOpacity(0.1),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            child:
            const Text('Cancel', style: TextStyle(color: kPrimaryColor)),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

