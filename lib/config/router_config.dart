import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_library_screen.dart';
import '../screens/admin/admin_login_screen.dart';
import '../screens/admin/user_insights_screen.dart';
import '../screens/admin/pending_approvals_screen.dart';
import '../screens/admin/church_admin_approvals_screen.dart';
import '../screens/admin/seller_approvals_screen.dart';
import '../screens/admin/news_approvals_screen.dart';
import '../screens/admin/event_approvals_screen.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/auth/email_verification_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/onboarding_flow_screen.dart';
import '../screens/auth/reset_password_screen.dart';
import '../screens/update/update_required_screen.dart';
import '../screens/banned/account_banned_screen.dart';
import '../screens/churches/church_announcements_screen.dart';
import '../screens/churches/claim_church_screen.dart';
import '../screens/churches/edit_church_screen.dart';
import '../screens/churches/suggest_church_screen.dart';
import '../screens/churches/suggest_edit_screen.dart';
import '../screens/home/post_notice_screen.dart';
import '../screens/home/search_screen.dart';
import '../screens/library/library_screen.dart';
import '../screens/profile/blocked_users_screen.dart';
import '../screens/profile/member_directory_screen.dart';
import '../screens/profile/my_directory_profile_screen.dart';
import '../screens/profile/my_events_screen.dart';
import '../screens/profile/notification_preferences_screen.dart';
import '../screens/profile/sabbath_timer_screen.dart';
import '../screens/profile/saved_listings_screen.dart';
import '../screens/utility/offline_screen.dart';
import '../screens/utility/report_submitted_screen.dart';
import '../services/church_service.dart';
import '../models/church_model.dart';
import '../screens/churches/church_details_screen.dart';
import '../screens/churches/churches_screen.dart';
import '../models/advent_news_model.dart';
import '../models/event_model.dart';
import '../models/job_model.dart';
import '../models/message_model.dart';
import '../models/prayer_model.dart';
import '../models/product_model.dart';
import '../models/seller_model.dart';
import '../screens/events/event_details_screen.dart';
import '../screens/events/events_screen.dart';
import '../screens/events/post_event_screen.dart';
import '../screens/jobs/job_details_screen.dart';
import '../screens/jobs/jobs_screen.dart';
import '../screens/jobs/post_job_screen.dart';
import '../screens/legal/guidelines_screen.dart';
import '../screens/legal/privacy_screen.dart';
import '../screens/legal/terms_screen.dart';
import '../screens/marketplace/add_product_screen.dart';
import '../screens/marketplace/category_screen.dart';
import '../screens/marketplace/marketplace_screen.dart';
import '../screens/marketplace/product_details_screen.dart';
import '../screens/messaging/chat_privacy_screen.dart';
import '../screens/messaging/chat_screen.dart';
import '../screens/messaging/conversations_screen.dart';
import '../screens/messaging/create_group_screen.dart';
import '../screens/messaging/group_info_screen.dart';
import '../screens/messaging/new_chat_screen.dart';
import '../screens/messaging/starred_messages_screen.dart';
import '../screens/news/advent_news_details_screen.dart';
import '../screens/news/advent_news_screen.dart';
import '../screens/news/post_advent_news_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/prayer/post_prayer_screen.dart';
import '../screens/prayer/prayer_details_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/prayer/prayer_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/feedback_screen.dart';
import '../screens/profile/notification_centre_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/users/user_profile_screen.dart';
import '../screens/seller/edit_store_screen.dart';
import '../screens/seller/manage_products_screen.dart';
import '../screens/seller/marketplace_guidelines_screen.dart';
import '../screens/seller/seller_dashboard_screen.dart';
import '../screens/seller/seller_profile_screen.dart';
import '../screens/seller/setup_store_screen.dart';
import '../screens/settings/about_screen.dart';
import '../screens/settings/permissions_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/splash/biometric_lock_screen.dart';
import '../screens/splash/splash_screen.dart';

/// A calm fade-through + gentle scale-up page transition. Used for the auth
/// screen so finishing the onboarding tour glides into sign-up instead of a
/// hard cut.
CustomTransitionPage<void> _fadeScalePage(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 520),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  debugLogDiagnostics: false,
  routes: [
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      // WhatsApp-style biometric lock. Splash routes here on cold
      // start when biometric is enabled; main.dart's resume handler
      // pushes here when the app returns from > 2 min in background.
      // Cancel keeps the user signed-in on this screen with Try Again,
      // never bounces to login.
      path: '/biometric-lock',
      name: 'biometric_lock',
      builder: (context, state) => const BiometricLockScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      name: 'onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/signup',
      name: 'signup',
      pageBuilder: (context, state) {
        final birthDate =
            state.extra is DateTime ? state.extra as DateTime : null;
        return _fadeScalePage(state, AuthScreen(birthDate: birthDate));
      },
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      pageBuilder: (context, state) {
        final birthDate =
            state.extra is DateTime ? state.extra as DateTime : null;
        return _fadeScalePage(state, AuthScreen(birthDate: birthDate));
      },
    ),
    GoRoute(
      path: '/email-verification',
      name: 'email_verification',
      builder: (context, state) {
        final email = state.extra is String ? state.extra as String : '';
        return EmailVerificationScreen(email: email);
      },
    ),
    GoRoute(
      path: '/profile-setup',
      name: 'profile_setup',
      builder: (context, state) => const OnboardingFlowScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      name: 'forgot_password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/reset-password',
      name: 'reset_password',
      builder: (context, state) => const ResetPasswordScreen(),
    ),
    GoRoute(
      path: '/update-required',
      name: 'update_required',
      builder: (context, state) => const UpdateRequiredScreen(),
    ),
    GoRoute(
      path: '/account-banned',
      name: 'account_banned',
      builder: (context, state) => const AccountBannedScreen(),
    ),
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'search',
          name: 'search',
          builder: (context, state) => const SearchScreen(),
        ),
        GoRoute(
          path: 'post-notice',
          name: 'post_notice',
          builder: (context, state) => const PostNoticeScreen(),
        ),
        GoRoute(
          path: 'notifications',
          name: 'notification_centre',
          builder: (context, state) => const NotificationCentreScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/churches',
      name: 'churches',
      builder: (context, state) => const ChurchesScreen(),
      routes: [
        GoRoute(
          path: 'suggest',
          name: 'suggest_church',
          builder: (context, state) => const SuggestChurchScreen(),
        ),
        GoRoute(
          path: ':id',
          name: 'church_details',
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            final initial = state.extra is Church ? state.extra as Church : null;
            return ChurchDetailsScreen(
              churchId: id,
              initialChurch: initial,
            );
          },
          routes: [
            GoRoute(
              path: 'announcements',
              name: 'church_announcements',
              builder: (context, state) {
                final church = state.extra as Church;
                return ChurchAnnouncementsScreen(church: church);
              },
            ),
            GoRoute(
              path: 'suggest-edit',
              name: 'suggest_edit',
              builder: (context, state) {
                final church = state.extra as Church;
                return SuggestEditScreen(church: church);
              },
            ),
            GoRoute(
              path: 'claim',
              name: 'claim_church',
              builder: (context, state) {
                final church = state.extra as Church;
                // Real claim flow: showcase the admin powers, then a short
                // contact form. Super-admin verifies on WhatsApp + approves.
                return ClaimChurchScreen(church: church);
              },
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/events',
      name: 'events',
      builder: (context, state) => const EventsScreen(),
      routes: [
        GoRoute(
          path: 'post',
          name: 'post_event',
          builder: (context, state) => const PostEventScreen(),
        ),
        GoRoute(
          path: 'edit',
          name: 'edit_event',
          builder: (context, state) {
            final existing =
                state.extra is Event ? state.extra as Event : null;
            return PostEventScreen(existing: existing);
          },
        ),
        GoRoute(
          path: ':id',
          name: 'event_details',
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            final initial = state.extra is Event ? state.extra as Event : null;
            return EventDetailsScreen(
              eventId: id,
              initialEvent: initial,
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/news',
      name: 'news',
      builder: (context, state) => const AdventNewsScreen(),
      routes: [
        GoRoute(
          path: 'post',
          name: 'post_news',
          builder: (context, state) {
            final existing =
                state.extra is AdventNews ? state.extra as AdventNews : null;
            return PostAdventNewsScreen(existing: existing);
          },
        ),
        GoRoute(
          path: ':id',
          name: 'news_details',
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            final initial =
                state.extra is AdventNews ? state.extra as AdventNews : null;
            return AdventNewsDetailsScreen(
              newsId: id,
              initialItem: initial,
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/prayer',
      name: 'prayer',
      builder: (context, state) => const PrayerScreen(),
      routes: [
        GoRoute(
          path: 'post',
          name: 'post_prayer',
          builder: (context, state) => const PostPrayerScreen(),
        ),
        GoRoute(
          path: 'edit',
          name: 'edit_prayer',
          builder: (context, state) {
            final existing =
                state.extra is Prayer ? state.extra as Prayer : null;
            return PostPrayerScreen(existing: existing);
          },
        ),
        GoRoute(
          path: ':id',
          name: 'prayer_details',
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            final initial =
                state.extra is Prayer ? state.extra as Prayer : null;
            return PrayerDetailsScreen(
              prayerId: id,
              initialPrayer: initial,
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/marketplace',
      name: 'marketplace',
      builder: (context, state) => const MarketplaceScreen(),
      routes: [
        GoRoute(
          path: 'add',
          name: 'add_product',
          builder: (context, state) => const AddProductScreen(),
        ),
        GoRoute(
          path: 'categories',
          name: 'categories',
          builder: (context, state) => const CategoryScreen(),
          routes: [
            GoRoute(
              path: ':id',
              name: 'category',
              builder: (context, state) => CategoryScreen(
                categoryId: state.pathParameters['id'],
              ),
            ),
          ],
        ),
        GoRoute(
          path: ':id',
          name: 'product_details',
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            final initial =
                state.extra is Product ? state.extra as Product : null;
            return ProductDetailsScreen(
              productId: id,
              initialProduct: initial,
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/jobs',
      name: 'jobs',
      builder: (context, state) => const JobsScreen(),
      routes: [
        GoRoute(
          path: 'post',
          name: 'post_job',
          builder: (context, state) => const PostJobScreen(),
        ),
        GoRoute(
          path: 'edit',
          name: 'edit_job',
          builder: (context, state) {
            final existing = state.extra is Job ? state.extra as Job : null;
            return PostJobScreen(existing: existing);
          },
        ),
        GoRoute(
          path: ':id',
          name: 'job_details',
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            final initial = state.extra is Job ? state.extra as Job : null;
            return JobDetailsScreen(
              jobId: id,
              initialJob: initial,
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/messages',
      name: 'messages',
      builder: (context, state) => ConversationsScreen(
        initialTab: state.uri.queryParameters['tab'],
      ),
      routes: [
        GoRoute(
          path: 'privacy',
          name: 'chat_privacy',
          builder: (context, state) => const ChatPrivacyScreen(),
        ),
        GoRoute(
          path: 'new-chat',
          name: 'new_chat',
          builder: (context, state) => const NewChatScreen(),
        ),
        GoRoute(
          path: 'new-group',
          name: 'create_group',
          builder: (context, state) =>
              CreateGroupScreen(preselectUserId: state.extra as String?),
        ),
        GoRoute(
          path: 'starred',
          name: 'starred_messages',
          builder: (context, state) => const StarredMessagesScreen(),
        ),
        GoRoute(
          path: ':id',
          name: 'chat',
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            // extra is either a Conversation (normal open) or a
            // (Conversation?, String?) record (open + scroll to a message,
            // from chat search).
            final extra = state.extra;
            Conversation? initial;
            String? highlight;
            if (extra is Conversation) {
              initial = extra;
            } else if (extra is (Conversation?, String?)) {
              initial = extra.$1;
              highlight = extra.$2;
            }
            return ChatScreen(
              conversationId: id,
              initialConversation: initial,
              highlightMessageId: highlight,
            );
          },
          routes: [
            GoRoute(
              path: 'info',
              name: 'group_info',
              builder: (context, state) => GroupInfoScreen(
                conversationId: state.pathParameters['id'] ?? '',
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfileScreen(),
      routes: [
        GoRoute(
          path: 'edit',
          name: 'edit_profile',
          builder: (context, state) => const EditProfileScreen(),
        ),
        GoRoute(
          path: 'my-events',
          name: 'my_events',
          builder: (context, state) => const MyEventsScreen(),
        ),
        GoRoute(
          path: 'saved-listings',
          name: 'saved_listings',
          builder: (context, state) => const SavedListingsScreen(),
        ),
        GoRoute(
          path: 'sabbath-timer',
          name: 'sabbath_timer',
          builder: (context, state) => const SabbathTimerScreen(),
        ),
        GoRoute(
          path: 'notifications',
          name: 'notification_preferences',
          builder: (context, state) =>
              const NotificationPreferencesScreen(),
        ),
        GoRoute(
          path: 'blocked',
          name: 'blocked_users',
          builder: (context, state) => const BlockedUsersScreen(),
        ),
        GoRoute(
          path: 'feedback',
          name: 'feedback',
          builder: (context, state) => const FeedbackScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/users/:userId',
      name: 'user_profile',
      builder: (context, state) => UserProfileScreen(
        userId: state.pathParameters['userId'] ?? '',
      ),
    ),
    GoRoute(
      path: '/library',
      name: 'library',
      // extra is an optional int initial tab (0=Bible,1=Hymnal,2=EGW,3=Music).
      builder: (context, state) =>
          LibraryScreen(initialTab: state.extra is int ? state.extra as int : 0),
    ),
    GoRoute(
      path: '/directory',
      name: 'member_directory',
      builder: (context, state) => const MemberDirectoryScreen(),
      routes: [
        GoRoute(
          path: 'me',
          name: 'my_directory_profile',
          builder: (context, state) => const MyDirectoryProfileScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/admin',
      name: 'admin_login',
      builder: (context, state) => const AdminLoginScreen(),
      routes: [
        GoRoute(
          path: 'dashboard',
          name: 'admin_dashboard',
          builder: (context, state) {
            final role = state.extra as ChurchAdminRole;
            return AdminDashboardScreen(role: role);
          },
          routes: [
            GoRoute(
              path: 'approvals',
              name: 'pending_approvals',
              builder: (context, state) {
                final role = state.extra as ChurchAdminRole;
                return PendingApprovalsScreen(role: role);
              },
            ),
            GoRoute(
              // Church-admin "Manage church info" editor (patch_121).
              path: 'edit-church',
              name: 'edit_church',
              builder: (context, state) {
                final role = state.extra as ChurchAdminRole;
                return EditChurchScreen(role: role);
              },
            ),
          ],
        ),
        GoRoute(
          // Super-admin seller approvals queue. Gated by the
          // is_super_admin profile flag on the server (patch_031)
          // and surfaced only from Settings → Admin → Seller
          // approvals so non-admin users never see the entry.
          path: 'sellers',
          name: 'admin_seller_approvals',
          builder: (context, state) => const SellerApprovalsScreen(),
        ),
        GoRoute(
          // Super-admin church-admin claim approvals (patch_112).
          path: 'church-admins',
          name: 'admin_church_approvals',
          builder: (context, state) => const ChurchAdminApprovalsScreen(),
        ),
        GoRoute(
          // Super-admin Advent News approvals queue (patch_047).
          path: 'news-approvals',
          name: 'admin_news_approvals',
          builder: (context, state) => const NewsApprovalsScreen(),
        ),
        GoRoute(
          path: 'event-approvals',
          name: 'admin_event_approvals',
          builder: (context, state) => const EventApprovalsScreen(),
        ),  
        GoRoute(
          // Super-admin Library content manager (patch_133): curate hymns +
          // upload music / EGW PDFs.
          path: 'library',
          name: 'admin_library',
          builder: (context, state) => const AdminLibraryScreen(),
        ),
        GoRoute(
          // Super-admin signup-survey insights (patch_136).
          path: 'insights',
          name: 'admin_user_insights',
          builder: (context, state) => const UserInsightsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/offline',
      name: 'offline',
      builder: (context, state) => const OfflineScreen(),
    ),
    GoRoute(
      path: '/report-submitted',
      name: 'report_submitted',
      builder: (context, state) => const ReportSubmittedScreen(),
    ),
    GoRoute(
      path: '/seller-profile/:userId',
      name: 'seller_profile',
      builder: (context, state) {
        final userId = state.pathParameters['userId'] ?? '';
        final initial = state.extra is Seller ? state.extra as Seller : null;
        return SellerProfileScreen(
          authUserId: userId,
          initialSeller: initial,
        );
      },
    ),
    GoRoute(
      path: '/seller',
      name: 'seller_dashboard',
      builder: (context, state) => const SellerDashboardScreen(),
      routes: [
        GoRoute(
          // Gate before the setup form — anyone authenticated lands
          // here first, must accept the Code of Conduct, then taps
          // Continue to push setup_store with the accepted version.
          path: 'guidelines',
          name: 'marketplace_guidelines',
          builder: (context, state) => const MarketplaceGuidelinesScreen(),
        ),
        GoRoute(
          path: 'setup',
          name: 'setup_store',
          builder: (context, state) {
            // termsVersion is carried via `extra` from the guidelines
            // gate. We default to "v1-2026-05" defensively so a code
            // path that lands here without the gate (e.g. a deep
            // link) still inserts a valid sellers row — but the
            // intended path is always guidelines → setup.
            final version =
                state.extra is String ? state.extra as String : 'v1-2026-05';
            return SetupStoreScreen(termsVersion: version);
          },
        ),
        GoRoute(
          path: 'edit',
          name: 'edit_store',
          builder: (context, state) {
            final seller =
                state.extra is Seller ? state.extra as Seller : null;
            return EditStoreScreen(initialSeller: seller);
          },
        ),
        GoRoute(
          path: 'products',
          name: 'manage_products',
          builder: (context, state) => const ManageProductsScreen(),
        ),
        GoRoute(
          path: 'products/edit',
          name: 'edit_product',
          builder: (context, state) {
            final product =
                state.extra is Product ? state.extra as Product : null;
            return AddProductScreen(initialProduct: product);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
      routes: [
        GoRoute(
          path: 'permissions',
          name: 'permissions',
          builder: (context, state) => const PermissionsScreen(),
        ),
        GoRoute(
          path: 'about',
          name: 'about',
          builder: (context, state) => const AboutScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/terms',
      name: 'terms',
      builder: (context, state) => const TermsScreen(),
    ),
    GoRoute(
      path: '/privacy',
      name: 'privacy',
      builder: (context, state) => const PrivacyScreen(),
    ),
    GoRoute(
      path: '/guidelines',
      name: 'guidelines',
      builder: (context, state) => const GuidelinesScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Text('Route not found: ${state.uri}'),
      ),
    ),
  ),
);
