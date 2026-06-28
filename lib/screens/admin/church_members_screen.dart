import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';

/// Church-admin "Members" — every member following this church, by name
/// (patch_139). Searchable. Tap a member to open their profile.
class ChurchMembersScreen extends StatefulWidget {
  const ChurchMembersScreen({super.key, required this.role});

  final ChurchAdminRole role;

  @override
  State<ChurchMembersScreen> createState() => _ChurchMembersScreenState();
}

class _ChurchMembersScreenState extends State<ChurchMembersScreen> {
  final _searchCtrl = TextEditingController();
  late Future<List<ChurchMember>> _future;
  List<ChurchMember> _all = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<ChurchMember>> _load() async {
    final list = await ChurchService.fetchMembers(widget.role.churchId);
    _all = list;
    return list;
  }

  List<ChurchMember> get _shown {
    if (_query.trim().isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all.where((m) => m.fullName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text('Members',
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 19)),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<ChurchMember>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primaryBlue));
            }
            if (_all.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.groups_outlined,
                          size: 60, color: palette.textMuted),
                      const SizedBox(height: 16),
                      Text('No members are following this church yet.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: palette.textMuted)),
                    ],
                  ),
                ),
              );
            }
            final shown = _shown;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    style:
                        AppTextStyles.bodyMedium.copyWith(color: palette.text),
                    decoration: InputDecoration(
                      hintText: 'Search members…',
                      hintStyle: TextStyle(color: palette.textMuted),
                      prefixIcon:
                          Icon(Icons.search, color: palette.textMuted),
                      filled: true,
                      fillColor: palette.inputFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: palette.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: palette.divider),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${_all.length} member(s)',
                        style: AppTextStyles.labelMedium
                            .copyWith(color: palette.textMuted)),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final m = shown[i];
                      return Material(
                        color: palette.card,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => context.pushNamed('user_profile',
                              pathParameters: {'userId': m.userId}),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: palette.divider),
                            ),
                            child: Row(
                              children: [
                                _Avatar(
                                    name: m.fullName,
                                    photoUrl: m.profilePhotoUrl),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(m.fullName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.titleSmall.copyWith(
                                          fontWeight: FontWeight.w600)),
                                ),
                                Icon(Icons.chevron_right,
                                    color: palette.textMuted),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photoUrl});
  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto ? null : AppColors.primaryGradient,
      ),
      child: hasPhoto
          ? CachedImage(photoUrl!, fit: BoxFit.cover)
          : Text(initial,
              style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.white, fontWeight: FontWeight.w700)),
    );
  }
}
