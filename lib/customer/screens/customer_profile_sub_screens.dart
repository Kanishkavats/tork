import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../common/constants/api_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../customer_app.dart';

// ─────────────────────────────────────────────────────────
//  HELPER WIDGETS (shared across sub-screens)
// ─────────────────────────────────────────────────────────

Color _pc() => CustomerApp.isPinkTheme.value ? const Color(0xFFEC4899) : const Color(0xFF3B82F6);

AppBar _buildSubAppBar(BuildContext context, String title) {
  return AppBar(
    backgroundColor: Colors.white,
    elevation: 0,
    centerTitle: true,
    title: Text(title, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18)),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
      onPressed: () => Navigator.pop(context),
    ),
  );
}

// ─────────────────────────────────────────────────────────
//  1. SAVED ADDRESSES
// ─────────────────────────────────────────────────────────

class CustomerSavedAddressesScreen extends StatefulWidget {
  const CustomerSavedAddressesScreen({super.key});
  @override
  State<CustomerSavedAddressesScreen> createState() => _CustomerSavedAddressesScreenState();
}

class _CustomerSavedAddressesScreenState extends State<CustomerSavedAddressesScreen> {
  final List<Map<String, dynamic>> _addresses = [
    {'type': 'Home', 'address': '12, MG Road, Bengaluru, Karnataka 560001', 'icon': Icons.home_rounded},
    {'type': 'Work', 'address': 'Prestige Tech Park, Whitefield, Bengaluru 560066', 'icon': Icons.work_rounded},
  ];

  void _showAddDialog() {
    final typeCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Address', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Label (e.g. Gym)')),
            const SizedBox(height: 12),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Full Address'), maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _pc(), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              if (typeCtrl.text.isNotEmpty && addrCtrl.text.isNotEmpty) {
                setState(() => _addresses.add({'type': typeCtrl.text, 'address': addrCtrl.text, 'icon': Icons.location_on_rounded}));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pc = _pc();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Saved Addresses'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: pc,
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add New', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _addresses.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.location_off_rounded, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text('No saved addresses', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _addresses.length,
              itemBuilder: (context, i) {
                final a = _addresses[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: pc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: Icon(a['icon'] as IconData, color: pc)),
                    title: Text(a['type'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(a['address'] as String, style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red), onPressed: () => setState(() => _addresses.removeAt(i))),
                  ),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  2. FAVOURITE PLACES
// ─────────────────────────────────────────────────────────

class CustomerFavouritePlacesScreen extends StatefulWidget {
  const CustomerFavouritePlacesScreen({super.key});
  @override
  State<CustomerFavouritePlacesScreen> createState() => _CustomerFavouritePlacesScreenState();
}

class _CustomerFavouritePlacesScreenState extends State<CustomerFavouritePlacesScreen> {
  final List<Map<String, dynamic>> _places = [
    {'name': 'Phoenix Mall', 'address': 'Whitefield, Bengaluru', 'icon': Icons.local_mall_rounded},
    {'name': 'Cubbon Park', 'address': 'Cubbon Park, Bengaluru', 'icon': Icons.park_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    final pc = _pc();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Favourite Places'),
      floatingActionButton: FloatingActionButton(backgroundColor: pc, onPressed: () {}, child: const Icon(Icons.add, color: Colors.white)),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _places.length,
        itemBuilder: (ctx, i) {
          final p = _places[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: pc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: Icon(p['icon'] as IconData, color: pc)),
              title: Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text(p['address'] as String, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black26),
              onTap: () {},
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  3. EMERGENCY CONTACTS
// ─────────────────────────────────────────────────────────

class CustomerEmergencyContactsScreen extends StatefulWidget {
  const CustomerEmergencyContactsScreen({super.key});
  @override
  State<CustomerEmergencyContactsScreen> createState() => _CustomerEmergencyContactsScreenState();
}

class _CustomerEmergencyContactsScreenState extends State<CustomerEmergencyContactsScreen> {
  final List<Map<String, String>> _contacts = [
    {'name': 'Mom', 'phone': '+91 98765 43210'},
    {'name': 'Dad', 'phone': '+91 87654 32109'},
  ];

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Emergency Contact', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _pc(), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
                setState(() => _contacts.add({'name': nameCtrl.text, 'phone': phoneCtrl.text}));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pc = _pc();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Emergency Contacts'),
      floatingActionButton: FloatingActionButton.extended(backgroundColor: pc, onPressed: _showAddDialog, icon: const Icon(Icons.person_add_rounded, color: Colors.white), label: const Text('Add Contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.orange.shade200)),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, color: Colors.orange.shade600),
              const SizedBox(width: 12),
              Expanded(child: Text('These contacts will be notified in case of an SOS emergency during your ride.', style: TextStyle(color: Colors.orange.shade700, fontSize: 13))),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _contacts.length,
              itemBuilder: (ctx, i) {
                final c = _contacts[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(backgroundColor: pc.withValues(alpha: 0.1), child: Text(c['name']![0], style: TextStyle(color: pc, fontWeight: FontWeight.bold, fontSize: 18))),
                    title: Text(c['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(c['phone']!, style: TextStyle(color: Colors.grey.shade500)),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red), onPressed: () => setState(() => _contacts.removeAt(i))),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  4. SUBSCRIPTION (with Razorpay)
// ─────────────────────────────────────────────────────────

class CustomerSubscriptionScreen extends StatefulWidget {
  const CustomerSubscriptionScreen({super.key});
  @override
  State<CustomerSubscriptionScreen> createState() => _CustomerSubscriptionScreenState();
}

class _CustomerSubscriptionScreenState extends State<CustomerSubscriptionScreen> {
  late Razorpay _razorpay;
  int _selectedPlan = 1; // 0=Monthly, 1=Yearly (default)
  bool _isProcessing = false;
  String _userPhone = '';

  final List<Map<String, dynamic>> _plans = [
    {'label': 'Monthly', 'price': 299, 'originalPrice': 399, 'period': '/month', 'saving': 'Save ₹100'},
    {'label': 'Yearly', 'price': 1999, 'originalPrice': 4788, 'period': '/year', 'saving': 'Save ₹2789 🔥'},
  ];

  final List<String> _benefits = [
    '✅ Priority ride matching',
    '✅ No surge pricing ever',
    '✅ Free cancellations (10/month)',
    '✅ Dedicated women-only driver pool',
    '✅ 24/7 premium support',
    '✅ Earn 2x referral rewards',
    '✅ Exclusive discount offers',
  ];

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userPhone = prefs.getString('user_phone') ?? '');
  }

  void _onSuccess(PaymentSuccessResponse resp) {
    if (mounted) {
      setState(() => _isProcessing = false);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('🎉 Subscription Active!', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Welcome to Torkk Premium! Enjoy all your exclusive benefits.'),
          actions: [ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _pc()), onPressed: () => Navigator.pop(ctx), child: const Text('Awesome!', style: TextStyle(color: Colors.white)))],
        ),
      );
    }
  }

  void _onError(PaymentFailureResponse resp) {
    if (mounted) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment failed: ${resp.message}'), backgroundColor: Colors.red));
    }
  }

  void _onExternalWallet(ExternalWalletResponse resp) {
    if (mounted) setState(() => _isProcessing = false);
  }

  Future<void> _subscribePlan() async {
    final plan = _plans[_selectedPlan];
    final amountPaise = (plan['price'] as int) * 100;
    setState(() => _isProcessing = true);

    try {
      final options = {
        'key': 'rzp_live_TAvPrH4AtVDEqF',
        'amount': amountPaise,
        'name': 'Torkk Premium',
        'description': 'Torkk Premium – ${plan['label']} Plan',
        'prefill': {
          'contact': _userPhone,
          'email': 'user@torkk.com',
        },
        'theme': {'color': CustomerApp.isPinkTheme.value ? '#EC4899' : '#3B82F6'},
      };
      _razorpay.open(options);
    } catch (e) {
      setState(() => _isProcessing = false);
      print('Razorpay error: $e');
    }
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pc = _pc();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Subscription'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [pc, pc.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 28),
                  const SizedBox(width: 8),
                  const Text('Torkk Premium', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                ]),
                const SizedBox(height: 8),
                const Text('Ride smarter. Pay less. Live better.', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ]),
            ),

            const SizedBox(height: 24),

            // Plan selector
            const Text('CHOOSE A PLAN', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Row(children: List.generate(_plans.length, (i) {
              final plan = _plans[i];
              final selected = _selectedPlan == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedPlan = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(right: i == 0 ? 8 : 0, left: i == 1 ? 8 : 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: selected ? pc : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: selected ? pc : Colors.grey.shade200, width: 2),
                      boxShadow: selected ? [BoxShadow(color: pc.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] : [],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(plan['label'] as String, style: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('₹${plan['price']}${plan['period']}', style: TextStyle(color: selected ? Colors.white : pc, fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(plan['saving'] as String, style: TextStyle(color: selected ? Colors.white70 : Colors.green.shade600, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              );
            })),

            const SizedBox(height: 24),

            // Benefits
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Premium Benefits', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  ..._benefits.map((b) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(b, style: const TextStyle(fontSize: 15)))),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Subscribe button
            GestureDetector(
              onTap: _isProcessing ? null : _subscribePlan,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: _isProcessing ? Colors.grey.shade300 : pc,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: pc.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))],
                ),
                child: Center(
                  child: _isProcessing
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text(
                          'Subscribe ₹${_plans[_selectedPlan]['price']}${_plans[_selectedPlan]['period']}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(child: Text('Cancel anytime · Secure payment via Razorpay', style: TextStyle(color: Colors.grey.shade500, fontSize: 12))),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  5. REFERRAL & REWARDS
// ─────────────────────────────────────────────────────────

class CustomerReferralScreen extends StatelessWidget {
  const CustomerReferralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pc = _pc();
    const referralCode = 'TORKK2025';
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Referral & Rewards'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Hero card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [pc, pc.withValues(alpha: 0.65)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(children: [
                const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 48),
                const SizedBox(height: 16),
                const Text('Invite Friends & Earn!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                const SizedBox(height: 8),
                const Text('You earn ₹50 and your friend gets ₹30 on their first ride.', style: TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                // Code box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(referralCode, style: TextStyle(color: pc, fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: 3)),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(const ClipboardData(text: referralCode));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral code copied!')));
                      },
                      child: Icon(Icons.copy_rounded, color: pc),
                    ),
                  ]),
                ),
              ]),
            ),

            const SizedBox(height: 24),

            // Stats
            Row(children: [
              _statCard('Referrals', '12', Icons.people_rounded, pc),
              const SizedBox(width: 12),
              _statCard('Rewards Earned', '₹600', Icons.currency_rupee_rounded, pc),
            ]),

            const SizedBox(height: 24),

            // How it works
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('How it works', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  _howStep('1', 'Share your code with friends', pc),
                  _howStep('2', 'They sign up & complete first ride', pc),
                  _howStep('3', 'You both earn ride credits!', pc),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color pc) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: pc, size: 28),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _howStep(String step, String text, Color pc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        CircleAvatar(radius: 14, backgroundColor: pc, child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  6. NOTIFICATION SETTINGS
// ─────────────────────────────────────────────────────────

class CustomerNotificationSettingsScreen extends StatefulWidget {
  const CustomerNotificationSettingsScreen({super.key});
  @override
  State<CustomerNotificationSettingsScreen> createState() => _CustomerNotificationSettingsScreenState();
}

class _CustomerNotificationSettingsScreenState extends State<CustomerNotificationSettingsScreen> {
  bool _pushRideUpdates = true;
  bool _pushOffers = true;
  bool _pushSOS = true;
  bool _smsUpdates = false;
  bool _emailReceipts = true;
  bool _whatsappUpdates = false;

  Widget _buildToggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    final pc = _pc();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ])),
        Switch(value: value, onChanged: onChanged, activeThumbColor: pc),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Notification Settings'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionLabel('Push Notifications'),
          _buildToggle('Ride Updates', 'Driver arrival, ride started, completed', _pushRideUpdates, (v) => setState(() => _pushRideUpdates = v)),
          _buildToggle('Offers & Promotions', 'Discounts, coupons, seasonal deals', _pushOffers, (v) => setState(() => _pushOffers = v)),
          _buildToggle('SOS Alerts', 'Emergency contact notifications', _pushSOS, (v) => setState(() => _pushSOS = v)),
          const SizedBox(height: 8),
          _sectionLabel('SMS'),
          _buildToggle('Ride SMS', 'OTP and status SMS messages', _smsUpdates, (v) => setState(() => _smsUpdates = v)),
          const SizedBox(height: 8),
          _sectionLabel('Email'),
          _buildToggle('Email Receipts', 'Get ride receipts in your email', _emailReceipts, (v) => setState(() => _emailReceipts = v)),
          const SizedBox(height: 8),
          _sectionLabel('WhatsApp'),
          _buildToggle('WhatsApp Updates', 'Receive ride updates on WhatsApp', _whatsappUpdates, (v) => setState(() => _whatsappUpdates = v)),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase(), style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
  );
}

// ─────────────────────────────────────────────────────────
//  7. PRIVACY SETTINGS
// ─────────────────────────────────────────────────────────

class CustomerPrivacySettingsScreen extends StatefulWidget {
  const CustomerPrivacySettingsScreen({super.key});
  @override
  State<CustomerPrivacySettingsScreen> createState() => _CustomerPrivacySettingsScreenState();
}

class _CustomerPrivacySettingsScreenState extends State<CustomerPrivacySettingsScreen> {
  bool _shareLocation = true;
  bool _shareProfilePhoto = false;
  bool _dataAnalytics = true;
  bool _twoFactorAuth = false;

  Widget _buildToggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    final pc = _pc();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ])),
        Switch(value: value, onChanged: onChanged, activeThumbColor: pc),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Privacy Settings'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildToggle('Location Sharing', 'Share live location with driver', _shareLocation, (v) => setState(() => _shareLocation = v)),
          _buildToggle('Show Profile Photo to Driver', 'Your photo is visible to driver during ride', _shareProfilePhoto, (v) => setState(() => _shareProfilePhoto = v)),
          _buildToggle('Analytics & Improvement', 'Help improve Torkk experience', _dataAnalytics, (v) => setState(() => _dataAnalytics = v)),
          _buildToggle('Two-Factor Authentication', 'Extra security on login', _twoFactorAuth, (v) => setState(() => _twoFactorAuth = v)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
              title: const Text('Delete Account', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: const Text('Permanently delete your Torkk account and data.', style: TextStyle(fontSize: 12)),
              onTap: () {},
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  8. LANGUAGE
// ─────────────────────────────────────────────────────────

class CustomerLanguageScreen extends StatefulWidget {
  const CustomerLanguageScreen({super.key});
  @override
  State<CustomerLanguageScreen> createState() => _CustomerLanguageScreenState();
}

class _CustomerLanguageScreenState extends State<CustomerLanguageScreen> {
  int _selected = 0;
  final List<Map<String, String>> _langs = [
    {'name': 'English', 'native': 'English'},
    {'name': 'Hindi', 'native': 'हिंदी'},
    {'name': 'Bengali', 'native': 'বাংলা'},
    {'name': 'Telugu', 'native': 'తెలుగు'},
    {'name': 'Marathi', 'native': 'मराठी'},
    {'name': 'Tamil', 'native': 'தமிழ்'},
    {'name': 'Kannada', 'native': 'ಕನ್ನಡ'},
  ];

  @override
  Widget build(BuildContext context) {
    final pc = _pc();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Language'),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _langs.length,
        itemBuilder: (ctx, i) {
          final selected = _selected == i;
          return GestureDetector(
            onTap: () => setState(() => _selected = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: selected ? pc.withValues(alpha: 0.07) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? pc : Colors.transparent, width: 2),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_langs[i]['name']!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: selected ? pc : const Color(0xFF0F172A))),
                  Text(_langs[i]['native']!, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                ])),
                if (selected) Icon(Icons.check_circle_rounded, color: pc),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  9. HELP & SUPPORT
// ─────────────────────────────────────────────────────────

class CustomerHelpSupportScreen extends StatefulWidget {
  const CustomerHelpSupportScreen({super.key});
  @override
  State<CustomerHelpSupportScreen> createState() => _CustomerHelpSupportScreenState();
}

class _CustomerHelpSupportScreenState extends State<CustomerHelpSupportScreen> {
  int? _openFaq;
  final List<Map<String, String>> _faqs = [
    {'q': 'How do I cancel a ride?', 'a': 'Go to Ride Tracking screen and tap the "Cancel Ride" button. Cancellation is free before the driver arrives.'},
    {'q': 'How does Torkk Wallet work?', 'a': 'Torkk Wallet lets you store money and pay for rides instantly. Add money via Razorpay and use it for seamless payments.'},
    {'q': 'Is it safe for women to ride alone?', 'a': 'Yes! Our women-only driver pool (pink theme) provides verified female drivers, SOS button, and live ride tracking shared with emergency contacts.'},
    {'q': 'How are fares calculated?', 'a': 'Fares = Base fare (₹79) + Distance fare (₹12/km) + Taxes (₹2). Surge pricing does not apply to Premium subscribers.'},
    {'q': 'How do I contact my driver?', 'a': 'Once a ride is accepted, you can call or message the driver directly from the Ride Tracking screen.'},
  ];

  @override
  Widget build(BuildContext context) {
    final pc = _pc();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Help & Support'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Contact options
          Row(children: [
            _contactCard(Icons.chat_bubble_outline_rounded, 'Live Chat', 'Chat with us', pc, () {}),
            const SizedBox(width: 12),
            _contactCard(Icons.email_outlined, 'Email Us', 'support@torkk.in', pc, () {}),
          ]),
          const SizedBox(height: 24),
          const Text('FREQUENTLY ASKED QUESTIONS', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          ..._faqs.asMap().entries.map((entry) {
            final i = entry.key;
            final faq = entry.value;
            final isOpen = _openFaq == i;
            return GestureDetector(
              onTap: () => setState(() => _openFaq = isOpen ? null : i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(faq['q']!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                    Icon(isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.grey),
                  ]),
                  if (isOpen) ...[
                    const SizedBox(height: 10),
                    Text(faq['a']!, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5)),
                  ],
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }

  Widget _contactCard(IconData icon, String title, String sub, Color pc, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: pc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: pc)),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text(sub, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  10. ABOUT TORKK
// ─────────────────────────────────────────────────────────

class CustomerAboutScreen extends StatelessWidget {
  const CustomerAboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pc = _pc();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'About Torkk'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [pc, pc.withValues(alpha: 0.65)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              CircleAvatar(radius: 40, backgroundColor: Colors.white.withValues(alpha: 0.2), child: const Icon(Icons.electric_bike_rounded, color: Colors.white, size: 44)),
              const SizedBox(height: 16),
              const Text('Torkk', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
              const SizedBox(height: 4),
              const Text('Version 1.0.0', style: TextStyle(color: Colors.white70, fontSize: 14)),
            ]),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: const Text(
              'Torkk is a next-generation ride-sharing platform designed with safety and convenience at its core. Our mission is to provide reliable, affordable, and secure transportation for everyone — with special focus on women\'s safety features like verified women-only driver pool, real-time SOS alerts, and ride sharing with trusted contacts.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.7),
            ),
          ),
          const SizedBox(height: 16),
          ...[['Founded', '2024'], ['Headquarters', 'Bengaluru, India'], ['Rides Completed', '50,000+'], ['Cities', 'Bengaluru, Hyderabad']].map((row) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(row[0], style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
              Text(row[1], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ]),
          )),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  11. TERMS & CONDITIONS
// ─────────────────────────────────────────────────────────

class CustomerTermsScreen extends StatelessWidget {
  const CustomerTermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Terms & Conditions'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Terms & Conditions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            SizedBox(height: 4),
            Text('Last updated: July 2025', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            SizedBox(height: 20),
            _TermsSection(title: '1. Acceptance of Terms', body: 'By using the Torkk application, you agree to be bound by these Terms and Conditions. If you do not agree, please do not use our services.'),
            _TermsSection(title: '2. User Eligibility', body: 'You must be at least 18 years of age to use our service. By creating an account, you confirm you meet this requirement.'),
            _TermsSection(title: '3. Booking & Cancellations', body: 'Rides can be cancelled free of charge before the driver is en route. Cancellation fees may apply after the driver departs. Repeated cancellations may result in account suspension.'),
            _TermsSection(title: '4. Payments', body: 'All payments are processed securely via Razorpay. Torkk Wallet funds are non-refundable once added. Disputes must be raised within 7 days of the transaction.'),
            _TermsSection(title: '5. User Conduct', body: 'Users must treat drivers with respect. Any abusive, violent, or discriminatory behavior will result in immediate account termination without refund.'),
            _TermsSection(title: '6. Privacy & Data', body: 'We collect location, payment, and usage data to improve the service. We never sell your personal data to third parties.'),
            _TermsSection(title: '7. Limitation of Liability', body: 'Torkk is not liable for delays, accidents, or third-party losses beyond our reasonable control. Our maximum liability is limited to the fare paid for the affected ride.'),
            _TermsSection(title: '8. Changes to Terms', body: 'Torkk reserves the right to modify these terms at any time. Continued use of the app constitutes acceptance of the updated terms.'),
          ]),
        ),
      ),
    );
  }
}

class _TermsSection extends StatelessWidget {
  final String title;
  final String body;
  const _TermsSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.6)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  12. PRIVACY POLICY
// ─────────────────────────────────────────────────────────

class CustomerPrivacyPolicyScreen extends StatelessWidget {
  const CustomerPrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildSubAppBar(context, 'Privacy Policy'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            SizedBox(height: 4),
            Text('Last updated: July 2025', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            SizedBox(height: 20),
            _TermsSection(title: '1. Information We Collect', body: 'We collect: (a) Personal info like name, phone number, and email at registration. (b) Location data during active rides. (c) Payment information processed via Razorpay. (d) Device and usage analytics.'),
            _TermsSection(title: '2. How We Use Your Data', body: 'Your data is used to match you with drivers, process payments, send ride updates, improve our services, and ensure platform safety.'),
            _TermsSection(title: '3. Data Sharing', body: 'We share data only with: (a) Your assigned driver (name, phone, photo). (b) Emergency contacts when SOS is triggered. (c) Razorpay for payment processing. We never sell your data.'),
            _TermsSection(title: '4. Data Security', body: 'All data is encrypted in transit (TLS 1.3) and at rest (AES-256). We regularly audit our security practices.'),
            _TermsSection(title: '5. Data Retention', body: 'Account data is retained for 3 years after last activity. You may request deletion at any time via Privacy Settings.'),
            _TermsSection(title: '6. Cookies', body: 'Our mobile app does not use browser cookies. We use device identifiers solely to maintain your session.'),
            _TermsSection(title: '7. Your Rights', body: 'You have the right to access, correct, or delete your personal data. Contact us at privacy@torkk.in for any data-related requests.'),
            _TermsSection(title: '8. Contact Us', body: 'For privacy concerns, email: privacy@torkk.in or write to: Torkk Technologies Pvt. Ltd., Bengaluru, Karnataka, India – 560001.'),
          ]),
        ),
      ),
    );
  }
}
