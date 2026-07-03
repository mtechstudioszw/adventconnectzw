import 'package:flutter/material.dart';
import '../../../widgets/screen_shell.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';

class LegalSection {
  const LegalSection({
    required this.title,
    required this.body,
    this.bullets = const [],
  });

  final String title;
  final String body;
  final List<String> bullets;
}

class LegalLayout extends StatefulWidget {
  const LegalLayout({
    super.key,
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.lastUpdated,
    required this.intro,
    required this.sections,
    this.draftNotice,
  });

  final String kicker;
  final String title;
  final String subtitle;
  final String lastUpdated;
  final String intro;
  final List<LegalSection> sections;

  /// When non-null, a prominent gold "DRAFT" banner is rendered above
  /// the intro card with this message. We use it to make it crystal
  /// clear that the text on screen is placeholder pending a lawyer's
  /// review and isn't a binding final document.
  final String? draftNotice;

  @override
  State<LegalLayout> createState() => _LegalLayoutState();
}

class _LegalLayoutState extends State<LegalLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildHero(context),
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) => Opacity(
                opacity: _fade.value,
                child: Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLastUpdated(),
                    if (widget.draftNotice != null) ...[
                      const SizedBox(height: 14),
                      _buildDraftBanner(),
                    ],
                    const SizedBox(height: 14),
                    _buildIntroCard(),
                    const SizedBox(height: 14),
                    _buildSectionsCard(),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        '© ${DateTime.now().year} Advent Connect ZW',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return ScreenHero(
      title: widget.title,
      tagline: widget.kicker,
      subtitle: widget.subtitle,
      fallbackRoute: 'settings',
    );
  }

  Widget _buildLastUpdated() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.update,
            color: AppColors.primaryBlue,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            'Last updated: ${widget.lastUpdated}',
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.goldAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.goldAccent.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.gavel,
            color: AppColors.goldAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DRAFT — pending legal review',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.goldAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.draftNotice!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textMuted,
                    height: 1.45,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        widget.intro,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textMuted,
          fontSize: 14.5,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildSectionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < widget.sections.length; i++) ...[
            _SectionBlock(
              index: i + 1,
              section: widget.sections[i],
            ),
            if (i != widget.sections.length - 1) ...[
              const SizedBox(height: 18),
               Divider(
                height: 1,
                color: AppColors.divider,
              ),
              const SizedBox(height: 18),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.index, required this.section});
  final int index;
  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$index',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                section.title,
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          section.body,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textMuted,
            fontSize: 14,
            height: 1.65,
          ),
        ),
        if (section.bullets.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final b in section.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      b,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

