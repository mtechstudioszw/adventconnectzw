/// Motion kit — one import for screens adopting the premium motion
/// language:
///
/// ```dart
/// import '../../widgets/motion/motion.dart';
/// ```
///
/// Pieces:
/// * [Pressable] — tap-down compress + spring-back for anything tappable
/// * [StaggeredReveal] — fade + rise entrance with per-item stagger
/// * [BrandedRefreshIndicator] — branded pull-to-refresh (drop-in for
///   Material's RefreshIndicator)
/// * [BrandSpinner] — branded indeterminate spinner
/// * [LoadingButton] — primary button that morphs into its loading state
/// * [ContentReveal] — skeleton → content crossfade
/// * [BrandFadeThroughTransitionsBuilder] — app-wide page transition
///   (registered in AppTheme, not used directly by screens)
library;

export 'brand_spinner.dart';
export 'branded_refresh_indicator.dart';
export 'content_reveal.dart';
export 'loading_button.dart';
export 'page_transitions.dart';
export 'pressable.dart';
export 'staggered_reveal.dart';
