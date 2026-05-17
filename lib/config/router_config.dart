import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_login_screen.dart';
import '../screens/admin/pending_approvals_screen.dart';
import '../screens/auth/age_verification_screen.dart';
import '../screens/auth/email_verification_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/profile_setup_church_screen.dart';
import '../screens/auth/profile_setup_screen.dart';
import '../screens/auth/reset_password_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/churches/church_announcements_screen.dart';
import '../screens/churches/claim_church_screen.dart';
import '../screens/churches/suggest_church_screen.dart';
import '../screens/churches/suggest_edit_screen.dart';
import '../screens/home/post_notice_screen.dart';
import '../screens/home/search_screen.dart';
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
import '../screens/messaging/chat_screen.dart';
import '../screens/messaging/conversations_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/prayer/post_prayer_screen.dart';
import '../screens/prayer/prayer_details_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/prayer/prayer_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/feedback_screen.dart';
import '../screens/profile/notification_centre_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/seller/edit_store_screen.dart';
import '../screens/seller/manage_products_screen.dart';
import '../screens/seller/seller_dashboard_screen.dart';
import '../screens/seller/seller_profile_screen.dart';
import '../screens/seller/setup_store_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/splash/splash_screen.dart';

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
      path: '/onboarding',
      name: 'onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/age-verification',
      name: 'age_verification',
      builder: (context, state) => const AgeVerificationScreen(),
    ),
    GoRoute(
      path: '/signup',
      name: 'signup',
      builder: (context, state) {
        final birthDate = state.extra is DateTime ? state.extra as DateTime : null;
        return SignupScreen(birthDate: birthDate);
      },
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
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
      builder: (context, state) => const ProfileSetupScreen(),
    ),
    GoRoute(
      path: '/profile-setup-church',
      name: 'profile_setup_church',
      builder: (context, state) => const ProfileSetupChurchScreen(),
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
      builder: (context, state) => const ConversationsScreen(),
      routes: [
        GoRoute(
          path: ':id',
          name: 'chat',
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            final initial = state.extra is Conversation
                ? state.extra as Conversation
                : null;
            return ChatScreen(
              conversationId: id,
              initialConversation: initial,
            );
          },
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
          ],
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
          path: 'setup',
          name: 'setup_store',
          builder: (context, state) => const SetupStoreScreen(),
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
      ],
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
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
