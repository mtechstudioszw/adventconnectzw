import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth/age_verification_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../models/church_model.dart';
import '../screens/churches/church_details_screen.dart';
import '../screens/churches/churches_screen.dart';
import '../models/event_model.dart';
import '../models/prayer_model.dart';
import '../models/product_model.dart';
import '../screens/events/event_details_screen.dart';
import '../screens/events/events_screen.dart';
import '../screens/marketplace/marketplace_screen.dart';
import '../screens/marketplace/product_details_screen.dart';
import '../screens/prayer/prayer_details_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/prayer/prayer_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/profile_screen.dart';
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
      path: '/home',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/churches',
      name: 'churches',
      builder: (context, state) => const ChurchesScreen(),
      routes: [
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
        ),
      ],
    ),
    GoRoute(
      path: '/events',
      name: 'events',
      builder: (context, state) => const EventsScreen(),
      routes: [
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
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfileScreen(),
      routes: [
        GoRoute(
          path: 'edit',
          name: 'edit_profile',
          builder: (context, state) => const EditProfileScreen(),
        ),
      ],
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
