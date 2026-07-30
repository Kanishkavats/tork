import 'package:flutter/material.dart';
import '../screens/customer_screens.dart';
import '../screens/customer_profile_sub_screens.dart';

class CustomerRoutes {
  static Map<String, WidgetBuilder> get routes {
    return {
      '/': (context) => const CustomerOnboardingScreen(),
      '/login': (context) => const CustomerOnboardingScreen(),
      '/home': (context) => const CustomerHomeScreen(),
      '/dashboard_male': (context) => const CustomerHomeScreen(),
      '/dashboard_female': (context) => const CustomerHomeScreen(),
      '/search': (context) => const CustomerSearchScreen(),
      '/booking': (context) => const CustomerBookingScreen(),
      '/tracking': (context) => const CustomerTrackingScreen(),
      '/payment': (context) => const CustomerPaymentScreen(),
      '/history': (context) => const CustomerRideHistoryScreen(),
      '/wallet': (context) => const CustomerWalletScreen(),
      '/ride-receipt': (context) => const CustomerRideReceiptScreen(),
      '/support': (context) => const CustomerSupportScreen(),
      '/profile': (context) => const CustomerProfileScreen(),
      '/notifications': (context) => const CustomerNotificationsScreen(),
      // Profile sub-screens
      '/profile/saved-addresses': (context) => const CustomerSavedAddressesScreen(),
      '/profile/favourite-places': (context) => const CustomerFavouritePlacesScreen(),
      '/profile/emergency-contacts': (context) => const CustomerEmergencyContactsScreen(),
      '/profile/subscription': (context) => const CustomerSubscriptionScreen(),
      '/profile/referral': (context) => const CustomerReferralScreen(),
      '/profile/notification-settings': (context) => const CustomerNotificationSettingsScreen(),
      '/profile/privacy-settings': (context) => const CustomerPrivacySettingsScreen(),
      '/profile/language': (context) => const CustomerLanguageScreen(),
      '/profile/help-support': (context) => const CustomerHelpSupportScreen(),
      '/profile/about': (context) => const CustomerAboutScreen(),
      '/profile/terms': (context) => const CustomerTermsScreen(),
      '/profile/privacy-policy': (context) => const CustomerPrivacyPolicyScreen(),
    };
  }
}
