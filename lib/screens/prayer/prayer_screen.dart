import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/prayer_model.dart';
import '../../services/prayer_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/prayer_card.dart';
import '../widgets/main_scaffold.dart';

class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  List<Prayer> _prayers = [];
  Set<String> _prayedIds = <String>{};
  Set<String> _busyIds = <String>{};
  bool _loading = true;

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
    _bootstrap();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        PrayerService.fetchPrayers(),
        PrayerService.fetchUserPrayedIds(),
      ]);
      if (!mounted) return;
      setState(() {
        _prayers = results[0] as List<Prayer>;
        _prayedIds = results[1] as Set<String>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _togglePray(Prayer prayer) async {
    if (_busyIds.contains(prayer.id)) return;
    setState(() => _busyIds = {..._busyIds, prayer.id});
    final wasPraying = _prayedIds.contains(prayer.id);
    try {
      if (wasPraying) {
        await PrayerService.unpray(prayer.id);
      } else {
        await PrayerService.pray(prayer.id);
      }
      if (!mounted) return;
      setState(() {
        if (wasPraying) {
          _prayedIds = _prayedIds.where((id) => id != prayer.id).toSet();
        } else {
          _prayedIds = {..._prayedIds, prayer.id};
        }
        _prayers = _prayers
            .map((p) => p.id == prayer.id
                ? p.copyWith(
                    prayerCount: wasPraying
                        ? (p.prayerCount - 1).clamp(0, 1 << 31)
                        : p.prayerCount + 1,
                  )
                : p)
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update prayer status.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(
            () => _busyIds = _busyIds.where((id) => id != prayer.id).toSet());
      }
    }
  }

  Future<void> _openPostSheet() async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PostPrayerSheet(),
    );
    if (posted == true) await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: 'Prayer',
      currentIndex: 3,
      body: Stack(
        children: [
          RefreshIndicator(
            color: AppColors.primaryBlue,
            onRefresh: _bootstrap,
            child: AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) => Opacity(
                opacity: _fade.value,
                child: Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: child,
                ),
              ),
              child: _buildList(),
            ),
          ),
          Positioned(
            right: 20,
            bottom: 20,
            child: _ShareFab(onTap: _openPostSheet),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _prayers.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_prayers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.volunteer_activism_outlined,
                    color: AppColors.primaryBlue,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Be the first to share',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Share a prayer request and pray together with the SDA community in Zimbabwe.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                _GradientButton(
                  label: 'Share a prayer',
                  onTap: _openPostSheet,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _prayers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final p = _prayers[i];
        return PrayerCard(
          prayer: p,
          isPraying: _prayedIds.contains(p.id),
          busy: _busyIds.contains(p.id),
          onTogglePray: () => _togglePray(p),
          onTap: () async {
            await context.pushNamed(
              'prayer_details',
              pathParameters: {'id': p.id},
              extra: p,
            );
            if (mounted) _bootstrap();
          },
        );
      },
    );
  }
}

class _ShareFab extends StatelessWidget {
  const _ShareFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, color: AppColors.white, size: 20),
                const SizedBox(width: 6),
                Text(
                  'Share prayer',
                  style: AppTextStyles.buttonText.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PostPrayerSheet extends StatefulWidget {
  const _PostPrayerSheet();

  @override
  State<_PostPrayerSheet> createState() => _PostPrayerSheetState();
}

class _PostPrayerSheetState extends State<_PostPrayerSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.length < 8) {
      setState(() => _error = 'Please write at least a few words.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PrayerService.postPrayer(text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not post your prayer. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(26, 26, 46, 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Share a prayer request',
                  style: AppTextStyles.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your community is here to pray with you.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.65),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 800,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'What would you like prayer for?',
                    filled: true,
                    fillColor: AppColors.lightGrey,
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color.fromRGBO(26, 26, 46, 0.06),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color.fromRGBO(26, 26, 46, 0.06),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.primaryBlue,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.red,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _GradientButton(
                  label: _busy ? 'Posting...' : 'Post prayer',
                  onTap: _busy ? null : _submit,
                  busy: _busy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onTap,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: AppColors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Text(
                        label,
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 15,
                          letterSpacing: 0.4,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
