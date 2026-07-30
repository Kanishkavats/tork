import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../customer_app.dart';
import '../../common/widgets/custom_button.dart';
import '../../common/widgets/custom_text_field.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../common/constants/api_constants.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// --- CUSTOMER ONBOARDING SCREEN (Steps 1 to 9) ---
class CustomerOnboardingScreen extends StatefulWidget {
  const CustomerOnboardingScreen({super.key});

  @override
  State<CustomerOnboardingScreen> createState() => _CustomerOnboardingScreenState();
}

class _CustomerOnboardingScreenState extends State<CustomerOnboardingScreen> with SingleTickerProviderStateMixin {
  static const String _baseUrl = ApiConstants.baseUrl;
  
  // _step:
  // 1: Splash Screen
  // 2: Enter Mobile Number
  // 3: OTP Verification
  // 4: Upload Aadhaar
  // 5: OCR Extracts Data
  // 6: Review & Confirm Details
  // 7: Complete Profile
  // 8: Biometric Setup
  // 9: Biometric Verify
  int _step = 1; 

  final _phoneController = TextEditingController(text: '98765 43210');
  final _otpController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();
  final _aadhaarNumberController = TextEditingController();
  String _selectedGender = 'Male';

  bool _isLoading = false;
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _aadhaarFrontImage;
  XFile? _aadhaarBackImage;

  // OTP Timer state
  Timer? _otpTimer;
  int _otpCountdown = 30;

  // OCR simulation progress
  double _ocrProgress = 0.0;
  Timer? _ocrTimer;
  bool _ocrRunning = false;

  @override
  void initState() {
    super.initState();
    // Splash screen transitions after 1.5s
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _step == 1) {
        setState(() {
          _step = 2;
        });
      }
    });
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    _ocrTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _aadhaarNumberController.dispose();
    super.dispose();
  }

  void _nextStep() {
    setState(() {
      _step++;
    });
  }

  void _prevStep() {
    if (_step > 1) {
      setState(() {
        _step--;
      });
    }
  }

  void _startOtpTimer() {
    _otpCountdown = 30;
    _otpTimer?.cancel();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_otpCountdown > 0) {
            _otpCountdown--;
          } else {
            _otpTimer?.cancel();
          }
        });
      }
    });
  }

  Future<void> _pickAadhaarImage(bool isFront, ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          if (isFront) {
            _aadhaarFrontImage = image;
          } else {
            _aadhaarBackImage = image;
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<http.Response> _callGeminiWithRetry(Uri uri, String body) async {
    int retryCount = 0;
    const int maxRetries = 3;
    Duration delay = const Duration(seconds: 2);

    while (true) {
      try {
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 429 && retryCount < maxRetries) {
          retryCount++;
          print('OCR Debug: Gemini 429 Rate Limit Hit. Retrying in ${delay.inSeconds} seconds... (Attempt $retryCount of $maxRetries)');
          await Future.delayed(delay);
          delay = delay * 2; // Exponential backoff
          continue;
        }
        return response;
      } catch (e) {
        if (retryCount < maxRetries) {
          retryCount++;
          print('OCR Debug: Gemini Request Exception: $e. Retrying in ${delay.inSeconds} seconds... (Attempt $retryCount of $maxRetries)');
          await Future.delayed(delay);
          delay = delay * 2;
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _processAadhaarOcr() async {
    if (_aadhaarFrontImage == null) {
      _completeOcrProcess();
      return;
    }
    try {
      final imageBytes = await _aadhaarFrontImage!.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final uri = Uri.parse('$_baseUrl/api/verify-aadhaar-ocr');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image})
      );

      if (response.statusCode == 200) {
        final extractedData = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            if (extractedData['name'] != null) _nameController.text = extractedData['name'];
            if (extractedData['dob'] != null) _dobController.text = extractedData['dob'];
            if (extractedData['gender'] != null) {
              _selectedGender = extractedData['gender'];
              CustomerApp.isPinkTheme.value = (_selectedGender == 'Female');
            }
            if (extractedData['aadhaar_number'] != null) {
              _aadhaarNumberController.text = extractedData['aadhaar_number'];
            }
          });
        }
      } else {
        print('OCR Debug: Backend OCR failed with status ${response.statusCode}');
      }
    } catch (e) {
      print('OCR Debug: Exception: $e');
    } finally {
      _completeOcrProcess();
    }
  }

  void _completeOcrProcess() {
    if (!mounted || !_ocrRunning) return;
    setState(() {
      _ocrRunning = false;
      _ocrProgress = 1.0;
      _ocrTimer?.cancel();
      
      if (_nameController.text.isEmpty) {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OCR extraction failed. Please enter details manually.')));
        }
      }
      _nextStep(); // Advance to Step 6 (Review & Confirm)
    });
  }

  void _startOcrSimulation() {
    if (_ocrRunning) return;
    _ocrRunning = true;
    _ocrProgress = 0.0;
    _ocrTimer?.cancel();
    
    // Start background live OCR processing immediately
    _processAadhaarOcr();

    // Increment progress bar to 90% and wait for the real OCR result to complete
    _ocrTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (mounted) {
        setState(() {
          if (_ocrProgress < 0.9) {
            _ocrProgress += 0.02;
          }
        });
      }
    });
  }

  Future<void> _uploadAndVerifyAadhaar() async {
    if (_aadhaarFrontImage == null || _aadhaarBackImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note: Simulating with default front/back cards.')),
      );
    }
    _nextStep(); // Advance to step 5 (OCR progress)
    _startOcrSimulation();
  }

  Future<void> _saveAadhaarDetailsToBackend() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse('$_baseUrl/api/verify-aadhaar');
      final cleanPhone = _phoneController.text.replaceAll(' ', '').replaceAll('-', '');
      print('Aadhaar Debug: Saving Aadhaar details to backend: $url for phone: $cleanPhone');

      String aadhaarPhotoBase64 = '';
      if (_aadhaarFrontImage != null) {
        final photoBytes = await _aadhaarFrontImage!.readAsBytes();
        aadhaarPhotoBase64 = base64Encode(photoBytes);
      }

      final body = json.encode({
        'phone': cleanPhone,
        'full_name': _nameController.text,
        'dob': _dobController.text,
        'gender': _selectedGender,
        'aadhaar_number': _aadhaarNumberController.text,
        'email': _emailController.text,
        'aadhaar_photo_base64': aadhaarPhotoBase64,
      });
      print('Aadhaar Debug: POST Body = $body');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 5));

      print('Aadhaar Debug: Backend Save Response Status = ${response.statusCode}');
      print('Aadhaar Debug: Backend Save Response Body = ${response.body}');

      if (response.statusCode != 200) {
        print('Aadhaar Debug: Failed to save to database. Status code: ${response.statusCode}. Continuing for demo.');
      }
    } catch (e) {
      print('Aadhaar Debug: Error saving Aadhaar to database: $e. Continuing for demo.');
    } finally {
      // DEMO BYPASS: Always save preferences and move forward regardless of network status
      final prefs = await SharedPreferences.getInstance();
      final cleanPhone = _phoneController.text.replaceAll(' ', '').replaceAll('-', '');
      await prefs.setString('user_name', _nameController.text);
      await prefs.setString('user_gender', _selectedGender);
      await prefs.setString('user_phone', cleanPhone);
      await prefs.setString('user_email', _emailController.text);
      await prefs.setBool('is_pink_theme', _selectedGender == 'Female');
      await prefs.setBool('isLoggedIn', true);
      CustomerApp.isPinkTheme.value = (_selectedGender == 'Female');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _navigateToDashboard();
      }
    }
  }

  Future<void> _sendLocalOtp(String phone) async {
    setState(() {
      _isLoading = true;
    });
    _startOtpTimer();

    try {
      final otpUrl = Uri.parse('$_baseUrl/api/send-otp');
      final otpResp = await http.post(
        otpUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'phone': phone.replaceAll(' ', '')}),
      ).timeout(const Duration(seconds: 5));

      if (otpResp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP sent to your mobile number')));
          setState(() {
            _isLoading = false;
            _step = 3; // Move to OTP screen
          });
        }
        return;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send OTP. Please try again.')));
        }
      }
    } catch (e) {
      print('OTP connection failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send OTP. Please check your connection.')));
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyLocalOtp() async {
    if (_otpController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter verification code.')),
      );
      return;
    }
    setState(() {
      _isLoading = true;
    });

    try {
      final verifyUrl = Uri.parse('$_baseUrl/api/verify-otp');
      final verifyResp = await http.post(
        verifyUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone': _phoneController.text.replaceAll(' ', ''),
          'code': _otpController.text,
        }),
      ).timeout(const Duration(seconds: 5));

      if (verifyResp.statusCode == 200) {
        final data = json.decode(verifyResp.body);
        final bool isExistingUser = data['is_existing_user'] == true;
        final String gender = data['gender'] ?? '';
        final String name = data['name'] ?? 'User';
        final String email = data['email'] ?? 'No email';

        if (isExistingUser) {
          setState(() {
            _selectedGender = gender.isNotEmpty ? gender : 'Male'; // default to Male if missing
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_gender', gender);
          await prefs.setString('user_name', name);
          await prefs.setString('user_email', email);
          await prefs.setString('user_phone', _phoneController.text.replaceAll(' ', ''));
          await prefs.setBool('isLoggedIn', true);
          await prefs.setBool('is_pink_theme', gender == 'Female');
          CustomerApp.isPinkTheme.value = (gender == 'Female');
          if (mounted) {
            _navigateToDashboard();
          }
          return;
        } else {
          setState(() {
            _isLoading = false;
            _step = 4;
          });
          return;
        }
      }
    } catch (e) {
      print('OTP Verification failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification failed. Invalid OTP.')));
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  void _navigateToDashboard() {
    if (_selectedGender == 'Female') {
      Navigator.pushReplacementNamed(context, '/dashboard_female');
    } else {
      Navigator.pushReplacementNamed(context, '/dashboard_male');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPink = _selectedGender == 'Female';
    final primaryColor = _step <= 6 
        ? Colors.black 
        : (isPink ? const Color(0xFFEC4899) : const Color(0xFF6366F1));

    return Scaffold(
      appBar: (_step > 1)
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _prevStep,
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
            )
          : null,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildStepContent(primaryColor, isPink),
        ),
      ),
    );
  }

  Widget _buildStepContent(Color primaryColor, bool isPink) {
    switch (_step) {
      case 1:
        return _buildStep1Splash(primaryColor);
      case 2:
        return _buildStep2MobileSelect(primaryColor);
      case 3:
        return _buildStep3OtpInput(primaryColor);
      case 4:
        return _buildStep4ProfileSetup(primaryColor);
      default:
        return _buildStep1Splash(primaryColor);
    }
  }

  // STEP 1: SPLASH SCREEN (1 SEC)
  Widget _buildStep1Splash(Color primaryColor) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.15),
                        blurRadius: 40,
                        spreadRadius: 8,
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/logo.jpeg',
                      height: 120,
                      width: 120,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 120,
                          height: 120,
                          color: primaryColor.withValues(alpha: 0.1),
                          child: Icon(Icons.directions_car_filled_rounded, size: 64, color: primaryColor),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'TORKK',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Safe Rides, Every Time',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey.shade400,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  // STEP 2: ENTER MOBILE NUMBER
  Widget _buildStep2MobileSelect(Color primaryColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Enter Mobile Number',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          Text(
            'We will send you an OTP to verify your number',
            style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 15),
          ),
          const SizedBox(height: 40),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Text(
                  '+91',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: const TextSelectionThemeData(
                      cursorColor: Colors.black,
                      selectionHandleColor: Colors.black,
                    ),
                  ),
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    cursorColor: Colors.black,
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      labelText: 'Mobile Number',
                      labelStyle: TextStyle(color: Colors.blueGrey.shade500, fontWeight: FontWeight.w600),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.black, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : BouncingWidget(
                  onTap: () => _sendLocalOtp(_phoneController.text),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Send OTP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // STEP 3: OTP VERIFICATION
  Widget _buildStep3OtpInput(Color primaryColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Enter OTP',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          Text(
            'We have sent a 6-digit OTP to +91 ${_phoneController.text}',
            style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 36),
          
          // OTP input boxes simulation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              String char = '';
              if (_otpController.text.length > index) {
                char = _otpController.text[index];
              }
              return Container(
                width: 48,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _otpController.text.length == index ? primaryColor : Colors.black12,
                    width: _otpController.text.length == index ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    char,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          // Hidden TextField to manage input easily
          Opacity(
            opacity: 0.0,
            child: SizedBox(
              height: 1,
              child: TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 6,
                onChanged: (val) {
                  setState(() {});
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _otpCountdown > 0 ? 'Resend OTP in 00:${_otpCountdown.toString().padLeft(2, '0')}' : 'Did not receive OTP?',
                style: TextStyle(color: Colors.blueGrey.shade400, fontWeight: FontWeight.w600),
              ),
              if (_otpCountdown == 0)
                TextButton(
                  onPressed: () => _sendLocalOtp(_phoneController.text),
                  child: Text('Resend OTP', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 40),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : BouncingWidget(
                  onTap: _verifyLocalOtp,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Verify & Continue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // STEP 4: PROFILE SETUP
  Widget _buildStep4ProfileSetup(Color primaryColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Profile Setup',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tell us your name and gender so we can personalize your rides.',
            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 32),

          Text(
            'Full Name',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              hintText: 'Enter your full name',
              hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontWeight: FontWeight.normal),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.black12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: primaryColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 28),

          Text(
            'Gender',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _genderCard(
                  title: 'Male',
                  icon: Icons.male_rounded,
                  isSelected: _selectedGender == 'Male',
                  onTap: () {
                    setState(() {
                      _selectedGender = 'Male';
                      CustomerApp.isPinkTheme.value = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _genderCard(
                  title: 'Female',
                  icon: Icons.female_rounded,
                  isSelected: _selectedGender == 'Female',
                  onTap: () {
                    setState(() {
                      _selectedGender = 'Female';
                      CustomerApp.isPinkTheme.value = true;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // Continue Button
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : BouncingWidget(
                  onTap: () {
                    if (_nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter your name.')),
                      );
                      return;
                    }
                    _saveAadhaarDetailsToBackend(); // Save profile & go straight to dashboard
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'CONTINUE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _genderCard({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            if (isSelected)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 14, color: Color(0xFF0F172A)),
                ),
              ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
                      border: isSelected ? Border.all(color: Colors.white24) : null,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: isSelected ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


}

// --- CUSTOMER HOME SCREEN (Dashboard & Ride state machine - Steps 10 to 24) ---
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> with TickerProviderStateMixin {
  static const String _baseUrl = ApiConstants.baseUrl;
  late AnimationController _animController;
  late AnimationController _rideAnimController;

  // _rideState transitions:
  // 10: Dashboard (Pickup/Drop off inputs)
  // 11: Select Vehicle (Vehicle options list)
  // 12: Own gender selection (universal, all vehicles)
  // 13: Fare Calculation loader
  // 14: Ride Settings (passenger count, driver-gender preview, offers/coupon, Proceed to Calculate Fare)
  // 15: Confirm Ride
  // 16: Searching Driver pulse
  // 17: Driver Accepted (Amit Kumar info)
  // 18: Driver Arriving (moving vehicle, ETA)
  // 19: Pickup Confirmed check screen
  // 20: Ride Started moving path
  // 21: Live Tracking active route
  // 22: Destination Reached
  // 23: Ride Completed payment receipt
  // 24: Rating & Feedback 5-star comments
  // 25: Biometric Verification (after own-gender selection, before Ride Settings)
  int _rideState = 10;

  String _pickupLocation = 'Sector 45, Gurugram';
  String _dropLocation = '';

  // Selected Vehicle
  String _selectedVehicleName = 'Cab';
  double _selectedVehiclePrice = 280.0;
  IconData _selectedVehicleIcon = Icons.directions_car_filled_rounded;
  int _selectedVehicleMaxSeats = 4;

  int _malePassengers = 1;
  int _femalePassengers = 0;
  bool _sameGenderRide = false;
  double _starRating = 5.0;
  String _ownGender = 'Male'; // Loaded from profile setup (SharedPreferences 'user_gender')
  bool _alternateGenderMode = false; // true = book this ride for the opposite gender
  bool _faceVerifiedOnce = false; // One-time face verification, done once ever
  bool _faceVerifyBusy = false;
  String? _scheduledDate;
  String? _scheduledTime;

  String get _alternateGenderLabel => _ownGender == 'Male' ? 'Female' : 'Male';
  String get _effectiveRideGender => _alternateGenderMode ? _alternateGenderLabel : _ownGender;

  // Step 25: Face Liveness (checked before every ride confirmation)
  final ImagePicker _rideImagePicker = ImagePicker();
  int _bioSubStep = 1; // 1: scan prompt, 2: verifying, 3: success
  String? _bioError;
  bool _bioBusy = false;
  String? _pickupOtp;
  bool _pickupShareShown = false;

  String get _derivedDriverGender => _malePassengers >= _femalePassengers ? 'Male' : 'Female';

  Timer? _stateTimer;

  GoogleMapController? _mapController;
  Position? _currentPosition;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  double? _dropLat;
  double? _dropLng;

  // Real Ride State Variables
  int? _activeRideId;
  double _estimatedFare = 0.0;
  double _estimatedDistance = 0.0;
  String _selectedVehicle = 'Cab';
  Timer? _statusPollTimer;
  StreamSubscription<Position>? _positionStream;
  late Razorpay _razorpay;

  // Matched Driver Details
  String? _driverName;
  String? _driverPhone;
  double? _driverRating;
  String? _driverPlateNumber;
  String? _driverVehicleModel;
  double? _driverLat;
  double? _driverLng;
  List<Map<String, dynamic>> _recentLocations = [];
  
  String _userName = 'User';
  String _userInitials = 'U';

  Future<void> _loadRecentLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recentsJson = prefs.getString('recent_locations');
    if (recentsJson != null) {
      final List<dynamic> decoded = json.decode(recentsJson);
      setState(() {
        _recentLocations = List<Map<String, dynamic>>.from(decoded);
      });
    }
  }

  Future<void> _saveRecentLocation(String name, double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    // Remove if exists to move to top
    _recentLocations.removeWhere((loc) => loc['name'] == name);
    _recentLocations.insert(0, {
      'name': name,
      'subtitle': 'Searched Location',
      'lat': lat,
      'lng': lng,
    });
    // Keep max 3
    if (_recentLocations.length > 3) {
      _recentLocations = _recentLocations.sublist(0, 3);
    }
    await prefs.setString('recent_locations', json.encode(_recentLocations));
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _loadRecentLocations();
    _initLocation();

    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          final isPink = CustomerApp.isPinkTheme.value;
          String defaultName = isPink ? 'Priya' : 'Rohan';
          _userName = prefs.getString('user_name') ?? defaultName;
          if (_userName.isEmpty) _userName = defaultName;
          _userInitials = _userName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join('').toUpperCase();
          _ownGender = prefs.getString('user_gender') ?? (isPink ? 'Female' : 'Male');
          _faceVerifiedOnce = prefs.getBool('face_verified_once') ?? false;
        });
      }
    });

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _rideAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _initLocation() async {
    print('DEBUG [MapScreen]: Starting _initLocation...');
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('DEBUG [MapScreen]: Location services are disabled.');
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        print('DEBUG [MapScreen]: Location permission denied, requesting permission...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('DEBUG [MapScreen]: Location permission was denied again.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('DEBUG [MapScreen]: Location permissions are permanently denied.');
        return;
      }

      print('DEBUG [MapScreen]: Permissions granted. Fetching current position...');
      final position = await Geolocator.getCurrentPosition();
      print('DEBUG [MapScreen]: Position fetched: ${position.latitude}, ${position.longitude}');

    String locationName = 'Current Location';
    try {
      final geoUrl = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1');
      final response = await http.get(
        geoUrl,
        headers: {'User-Agent': 'TorkkApp/1.0'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['display_name'] != null) {
          locationName = data['display_name'];
          if (locationName.length > 40) {
            final components = locationName.split(',');
            if (components.length >= 2) {
              locationName = '${components[0]}, ${components[1]}'.trim();
            }
          }
        }
      } else {
        print('Geocoding error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Geocoding exception: $e');
    }

    if (mounted) {
      setState(() {
        _currentPosition = position;
        _pickupLocation = locationName;
        _markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: LatLng(position.latitude, position.longitude),
            infoWindow: const InfoWindow(title: 'Your Location'),
          ),
        );
      });

      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 15.0,
            ),
          ),
        );
      }

      // Live Tracking to Backend
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';
      
      if (phone.isNotEmpty) {
        try {
          await UserService.updateCurrentLocation(
            phone: phone,
            latitude: position.latitude,
            longitude: position.longitude,
            address: locationName,
          );
        } catch (e) {
          print('DEBUG [MapScreen]: Failed initial location update: $e');
        }

        _positionStream = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1, // 1 meter threshold
          ),
        ).listen((Position livePos) async {
          print('DEBUG [MapScreen]: Live pos update: ${livePos.latitude}, ${livePos.longitude}');
          try {
            await UserService.updateCurrentLocation(
              phone: phone,
              latitude: livePos.latitude,
              longitude: livePos.longitude,
              address: _pickupLocation, 
            );
          } catch (e) {
            print('DEBUG [MapScreen]: Failed live location update: $e');
          }
        });
      }
      }
    } catch (e, stacktrace) {
      print('DEBUG [MapScreen]: Exception in _initLocation: $e');
      print('DEBUG [MapScreen]: Stacktrace: $stacktrace');
    }
  }

  @override
  void dispose() {
    _razorpay.clear();
    _animController.dispose();
    _rideAnimController.dispose();
    _stateTimer?.cancel();
    _statusPollTimer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  void _startProgressSimulation(int nextState, int seconds) {
    _rideAnimController.reset();
    _rideAnimController.duration = Duration(seconds: seconds);
    _rideAnimController.forward();

    _stateTimer?.cancel();
    _stateTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) {
        setState(() {
          _rideState = nextState;
          _triggerStateAction();
        });
      }
    });
  }

  double _applyDiscount(double baseFare, {String? vehicleName}) {
    final promo = CustomerApp.activePromo.value;
    if (promo == null) return baseFare;
    final condition = promo['condition'];
    if (condition != null && condition != vehicleName) return baseFare;
    double discount = 0;
    if (promo['type'] == 'percentage') {
      discount = baseFare * (promo['value'] as int) / 100;
      final max = promo['max'];
      if (max != null && discount > (max as int)) discount = max.toDouble();
    } else if (promo['type'] == 'flat') {
      discount = (promo['value'] as int).toDouble();
    }
    final result = baseFare - discount;
    return result < 0 ? baseFare : result;
  }

  Future<void> _estimateRide() async {
    if (_currentPosition == null || _dropLocation.isEmpty) return;
    setState(() => _rideState = 13); // Show calculating fare loader
    try {
      final res = await RideService.estimateRide(
        pickupLat: _currentPosition!.latitude,
        pickupLng: _currentPosition!.longitude,
        dropLat: _currentPosition!.latitude + 0.05, // Mock drop lat
        dropLng: _currentPosition!.longitude + 0.05, // Mock drop lng
        vehicle: _selectedVehicle,
      );
      if (mounted) {
        setState(() {
          _estimatedDistance = res['distance_km'].toDouble();
          _estimatedFare = _applyDiscount(res['fare'].toDouble(), vehicleName: _selectedVehicle);
          _selectedVehiclePrice = _estimatedFare;
          // Face verification is now a one-time step on the Select Vehicle screen, not every ride.
          // _bioSubStep = 1;
          // _bioError = null;
          // _rideState = 25;
          _rideState = 15;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error calculating fare: $e')));
        setState(() => _rideState = 11);
      }
    }
  }

  Future<void> _requestRide() async {
    if (_currentPosition == null) return;
    setState(() => _rideState = 16); // Finding Driver loader
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '1234567890';

      final result = await RideService.requestRide(
        phone: phone,
        pickupLat: _currentPosition!.latitude,
        pickupLng: _currentPosition!.longitude,
        pickupAddress: _pickupLocation,
        dropLat: _currentPosition!.latitude + 0.05,
        dropLng: _currentPosition!.longitude + 0.05,
        dropAddress: _dropLocation,
        vehicle: _selectedVehicle,
        distanceKm: _estimatedDistance,
        fare: _estimatedFare,
        malePassengers: _malePassengers,
        femalePassengers: _femalePassengers,
      );
      _activeRideId = result['ride_id'] as int;
      _pickupOtp = result['pickup_otp'] as String?;

      // Start polling
      _pollRideStatus();
    } catch (e) {
      print('Ride Request DEBUG: catch block caught error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error requesting ride: $e')));
        setState(() => _rideState = 15);
      }
    }
  }


  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  Future<void> _drawRouteBetween({

    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    required String polylineId,
    required Color color,
  }) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    final url = Uri.parse('https://maps.googleapis.com/maps/api/directions/json?origin=$startLat,$startLng&destination=$endLat,$endLng&key=$apiKey');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;
        if (routes.isNotEmpty) {
          final polylineStr = routes[0]['overview_polyline']['points'];
          List<LatLng> polylineCoordinates = _decodePolyline(polylineStr);

          setState(() {
            _polylines.removeWhere((p) => p.polylineId.value == polylineId);
            _polylines.add(
              Polyline(
                polylineId: PolylineId(polylineId),
                color: color,
                width: 4,
                points: polylineCoordinates,
              ),
            );
          });
        }
      }
    } catch (e) {
      print('Route generation error: $e');
    }
  }

  // TEMP: Disabled for customer-only delivery.
  void _pollRideStatus() {
    _statusPollTimer?.cancel();
    // Driver matching/tracking integration disabled below; call site kept as a no-op.
    return;
    // _statusPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
    //   if (_activeRideId == null) {
    //     timer.cancel();
    //     return;
    //   }
    //   try {
    //     final statusRes = await RideService.getRideStatus(_activeRideId!);
    //     final status = statusRes['ride_status'];
    //     final isPickedUp = statusRes['is_picked_up'] ?? false;
    //     final isDropped = statusRes['is_dropped'] ?? false;
    //     final justPickedUp = isPickedUp && _rideState != 21 && !_pickupShareShown;
    //
    //     if (mounted) {
    //       setState(() {
    //         if (statusRes['pickup_otp'] != null) {
    //           _pickupOtp = statusRes['pickup_otp'] as String?;
    //         }
    //         // Update driver details if present
    //         if (statusRes['driver_name'] != null && (statusRes['driver_name'] as String).isNotEmpty) {
    //           _driverName = statusRes['driver_name'];
    //           _driverPhone = statusRes['driver_phone'];
    //           _driverRating = (statusRes['driver_rating'] as num?)?.toDouble() ?? 5.0;
    //           _driverPlateNumber = statusRes['driver_plate_number'] != null && (statusRes['driver_plate_number'] as String).isNotEmpty
    //               ? statusRes['driver_plate_number']
    //               : 'HR55AB1234';
    //           _driverVehicleModel = statusRes['driver_vehicle_model'] != null && (statusRes['driver_vehicle_model'] as String).isNotEmpty
    //               ? statusRes['driver_vehicle_model']
    //               : 'White Sedan';
    //         }
    //
    //         if (statusRes['driver_lat'] != null && statusRes['driver_lng'] != null) {
    //           _driverLat = (statusRes['driver_lat'] as num).toDouble();
    //           _driverLng = (statusRes['driver_lng'] as num).toDouble();
    //
    //           // Update driver marker
    //           _markers.removeWhere((m) => m.markerId.value == 'driver');
    //           _markers.add(
    //             Marker(
    //               markerId: const MarkerId('driver'),
    //               position: LatLng(_driverLat!, _driverLng!),
    //               icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    //               infoWindow: const InfoWindow(title: 'Driver Location'),
    //             ),
    //           );
    //         }
    //
    //         if (status == 'accepted') {
    //           if (_rideState != 17 && _rideState != 18) {
    //             _rideState = 17; // Driver matching done, showing details
    //           }
    //
    //           // Draw path from driver's current position to pickup location
    //           if (_driverLat != null && _driverLng != null && _currentPosition != null) {
    //             _drawRouteBetween(
    //               startLat: _driverLat!,
    //               startLng: _driverLng!,
    //               endLat: _currentPosition!.latitude,
    //               endLng: _currentPosition!.longitude,
    //               polylineId: 'route',
    //               color: Colors.blueAccent,
    //             );
    //           }
    //         } else if (status == 'in_progress') {
    //           if (isPickedUp) {
    //             _rideState = 21; // Live tracking
    //
    //             // Draw path from pickup to drop location
    //             if (_currentPosition != null && _dropLat != null && _dropLng != null) {
    //               _drawRouteBetween(
    //                 startLat: _currentPosition!.latitude,
    //                 startLng: _currentPosition!.longitude,
    //                 endLat: _dropLat!,
    //                 endLng: _dropLng!,
    //                 polylineId: 'route',
    //                 color: CustomerApp.isPinkTheme.value ? const Color(0xFFEC4899) : const Color(0xFF6366F1),
    //               );
    //             }
    //           } else {
    //             // Driver is heading to pickup location
    //             if (_rideState != 17 && _rideState != 18) {
    //               _rideState = 18; // Show driver arriving panel
    //             }
    //
    //             // Draw path from driver's current position to pickup location
    //             if (_driverLat != null && _driverLng != null && _currentPosition != null) {
    //               _drawRouteBetween(
    //                 startLat: _driverLat!,
    //                 startLng: _driverLng!,
    //                 endLat: _currentPosition!.latitude,
    //                 endLng: _currentPosition!.longitude,
    //                 polylineId: 'route',
    //                 color: Colors.blueAccent,
    //               );
    //             }
    //           }
    //         } else if (status == 'completed' || isDropped) {
    //           timer.cancel();
    //           _rideState = 22; // Destination reached!
    //           _polylines.clear();
    //         }
    //
    //         if (justPickedUp) {
    //           _pickupShareShown = true;
    //         }
    //       });
    //     }
    //   } catch (e) {
    //     print('Polling error: $e');
    //   }
    // });
  }

  Future<void> _startRazorpayPayment() async {
    if (_activeRideId == null) return;

    try {
      final orderResponse = await http.post(
        Uri.parse('$_baseUrl/api/payments/create-order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': _activeRideId,
          'amount': _selectedVehiclePrice,
        }),
      );
      if (orderResponse.statusCode != 200) {
        throw Exception('Failed to create payment order: ${orderResponse.body}');
      }
      final orderData = jsonDecode(orderResponse.body) as Map<String, dynamic>;
      final amountPaise = orderData['amount_paise'] ?? (_selectedVehiclePrice * 100).round();
      final orderId = orderData['order_id'] as String?;
      final razorpayKey = orderData['key'] as String? ?? dotenv.env['RAZORPAY_KEY'];
      if (orderId == null || razorpayKey == null) {
        throw Exception('Payment order missing order_id/key');
      }

      final prefill = <String, String>{'email': 'customer@torkk.com'};
      if (_driverPhone != null && _driverPhone!.isNotEmpty) {
        prefill['contact'] = _driverPhone!;
      }
      final options = {
        'key': razorpayKey,
        'amount': amountPaise,
        'order_id': orderId,
        'name': 'Torkk Ride Payment',
        'description': 'Payment for Ride ID: $_activeRideId',
        'prefill': prefill,
      };
      _razorpay.open(options);
    } catch (e) {
      print('Razorpay error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open Razorpay: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    print('Razorpay Payment Success: txnId=${response.paymentId}');
    final transactionId = response.paymentId ?? 'txn_${DateTime.now().millisecondsSinceEpoch}';
    final upiId = 'upi_razorpay'; 

    try {
      final uri = Uri.parse('$_baseUrl/api/payments/verify');
      final verifyResponse = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': _activeRideId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_order_id': response.orderId,
          'razorpay_signature': response.signature
        })
      );
      if (verifyResponse.statusCode != 200) {
        throw Exception('Payment verification failed: ${verifyResponse.body}');
      }

      await RideService.savePayment(
        rideId: _activeRideId!,
        transactionId: transactionId,
        upiId: upiId,
      );
      
      setState(() {
        _rideState = 23; // Advance to Receipt / Completed screen
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment Successful! Thank you for riding with Torkk.'), backgroundColor: Colors.green),
      );
    } catch (e) {
      print('Error saving payment status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment saved locally, but failed to sync to server: $e'), backgroundColor: Colors.orange),
      );
      setState(() {
        _rideState = 23;
      });
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    print('Razorpay Payment Error: ${response.code} - ${response.message}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment Failed: ${response.message ?? "Unknown Error"}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print('Razorpay External Wallet: ${response.walletName}');
  }

  Future<void> _triggerSOS() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    
    if (_currentPosition != null) {
      try {
        await RideService.triggerSOS(
          rideId: _activeRideId,
          phone: phone,
          lat: _currentPosition!.latitude,
          lng: _currentPosition!.longitude,
        );
      } catch (e) {
        print("Failed to send SOS to backend: $e");
      }
    }
  }

  void _triggerStateAction() {
    if (_rideState == 13) {
      // Calculate Fare Loader -> Auto Apply Coupon
      _startProgressSimulation(14, 2);
    } else if (_rideState == 16) {
      // Searching Driver -> Driver Accepted
      _startProgressSimulation(17, 3);
    } else if (_rideState == 18) {
      // Driver Arriving simulation
      _startProgressSimulation(19, 4);
    } else if (_rideState == 19) {
      // Pickup Confirmed -> Ride Started
      _startProgressSimulation(20, 2);
    } else if (_rideState == 20) {
      // Ride Started -> Live Tracking
      _startProgressSimulation(21, 3);
    } else if (_rideState == 21) {
      // Live Tracking -> Reached
      _startProgressSimulation(22, 3);
    }
  }

  Future<void> _drawRoute() async {
    if (_currentPosition == null || _dropLat == null || _dropLng == null) return;
    final startLat = _currentPosition!.latitude;
    final startLng = _currentPosition!.longitude;
    final endLat = _dropLat!;
    final endLng = _dropLng!;

    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    final url = Uri.parse('https://maps.googleapis.com/maps/api/directions/json?origin=$startLat,$startLng&destination=$endLat,$endLng&key=$apiKey');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;
        if (routes.isNotEmpty) {
          final polylineStr = routes[0]['overview_polyline']['points'];
          List<LatLng> polylineCoordinates = _decodePolyline(polylineStr);

          setState(() {
            _polylines.clear();
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                color: CustomerApp.isPinkTheme.value ? const Color(0xFFEC4899) : const Color(0xFF6366F1),
                width: 4,
                points: polylineCoordinates,
              ),
            );

            _markers.add(
              Marker(
                markerId: const MarkerId('drop_location'),
                position: LatLng(endLat, endLng),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              ),
            );
          });

          if (_mapController != null) {
            LatLngBounds bounds;
            if (startLat > endLat && startLng > endLng) {
              bounds = LatLngBounds(southwest: LatLng(endLat, endLng), northeast: LatLng(startLat, startLng));
            } else if (startLng > endLng) {
              bounds = LatLngBounds(southwest: LatLng(startLat, endLng), northeast: LatLng(endLat, startLng));
            } else if (startLat > endLat) {
              bounds = LatLngBounds(southwest: LatLng(endLat, startLng), northeast: LatLng(startLat, endLng));
            } else {
              bounds = LatLngBounds(southwest: LatLng(startLat, startLng), northeast: LatLng(endLat, endLng));
            }
            _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50.0));
          }
        }
      }
    } catch (e) {
      print('Route generation error: $e');
    }
  }

  void _resetFlow() {
    setState(() {
      _rideState = 10;
      _dropLocation = '';
      _dropLat = null;
      _dropLng = null;
      _polylines.clear();
      _markers.removeWhere((m) => m.markerId.value == 'drop_location');
      _activeRideId = null;
      _malePassengers = 1;
      _femalePassengers = 0;
      _sameGenderRide = false;
      _starRating = 5.0;
      _scheduledDate = null;
      _scheduledTime = null;
      _pickupOtp = null;
      _pickupShareShown = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPink = CustomerApp.isPinkTheme.value;
    final primaryColor = isPink ? const Color(0xFFEC4899) : const Color(0xFF6366F1);

    return Scaffold(
      drawer: Drawer(
        child: Container(
          color: const Color(0xFF0F172A),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              FutureBuilder<SharedPreferences>(
                future: SharedPreferences.getInstance(),
                builder: (context, snapshot) {
                  final name = snapshot.data?.getString('user_name') ?? 'Guest User';
                  final phone = snapshot.data?.getString('user_phone') ?? '';
                  return DrawerHeader(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [primaryColor, primaryColor.withValues(alpha: 0.8)]),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.person_rounded, size: 32, color: Colors.white),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          name,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                        ),
                        Text(
                          phone,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                },
              ),
              _buildDrawerItem(Icons.home_rounded, 'Dashboard Home', () {
                Navigator.pop(context);
                _resetFlow();
              }),
              _buildDrawerItem(Icons.history_rounded, 'Ride History', () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/history');
              }),
              _buildDrawerItem(Icons.support_agent_rounded, 'Support Help', () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/support');
              }),
              const Divider(color: Colors.white12, height: 32, thickness: 1),
              _buildDrawerItem(Icons.logout_rounded, 'Logout', () {
                Navigator.pushReplacementNamed(context, '/');
              }, isDestructive: true),
            ],
          ),
        ),
      ),
      floatingActionButton: _rideState != 10
          ? FloatingActionButton(
              onPressed: () => _showSafetySupportOverlay(primaryColor),
              backgroundColor: Colors.redAccent,
              elevation: 6,
              child: const Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          : null,
      bottomNavigationBar: _rideState == 10 ? _buildBottomNavBar(isPink) : null,
      body: _rideState == 10
          ? _buildFullScreenDashboard(primaryColor, isPink)
          : Stack(
              children: [
                // 1. Google Map (replacing MockMapPainter)
                _currentPosition == null
                    ? const Center(child: CircularProgressIndicator())
                    : GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                          zoom: 15.0,
                        ),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        markers: _markers,
                        polylines: _polylines,
                        onMapCreated: (controller) {
                          _mapController = controller;
                        },
                      ),
                // 4. State-based overlay panel sheets
                _buildStatePanel(primaryColor),
              ],
            ),
    );
  }

  Widget _buildFullScreenDashboard(Color primaryColor, bool isPink) {
    final bgColor = const Color(0xFF1E1E1E); // dark grey
    final headerBgColor = isPink ? const Color(0xFFFDE4F2) : const Color(0xFFE8F0FF);
    final promoBgColor = isPink ? const Color(0xFFC82665) : const Color(0xFF255EE6);
    final avatarColor = isPink ? const Color(0xFFEE4984) : const Color(0xFF295CFF);
    final mapPinColor = isPink ? const Color(0xFFF43F5E) : const Color(0xFF2954FF);
    
    // First name only for the greeting
    final firstName = _userName.split(' ').first;

    return Container(
      color: bgColor,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 24, top: 16, bottom: 16),
              child: Text('Home Page', style: TextStyle(color: Colors.white60, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Greeting + Avatar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Good afternoon', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                Text('Hi, $firstName', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pushNamed(context, '/profile'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: avatarColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(_userInitials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Live Location Map
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: headerBgColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: _currentPosition == null
                                ? const Center(child: CircularProgressIndicator())
                                : GoogleMap(
                                    initialCameraPosition: CameraPosition(
                                      target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                                      zoom: 15.0,
                                    ),
                                    myLocationEnabled: true,
                                    myLocationButtonEnabled: false,
                                    zoomControlsEnabled: false,
                                    markers: _markers,
                                  ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Search Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: BouncingWidget(
                          onTap: () async {
                            final result = await Navigator.pushNamed(
                              context, 
                              '/search',
                              arguments: {
                                'pickup': _pickupLocation,
                                'drop': _dropLocation,
                                'pickupLat': _currentPosition?.latitude,
                                'pickupLng': _currentPosition?.longitude,
                              },
                            );
                            if (result != null && result is Map<String, dynamic>) {
                              setState(() {
                                _pickupLocation = result['pickup'] as String? ?? 'Sector 45, Gurugram';
                                _dropLocation = result['drop'] as String? ?? 'DLF Cyber City, Gurugram';
                                final latStr = result['dropLat'] as String?;
                                final lngStr = result['dropLng'] as String?;
                                if (latStr != null) _dropLat = double.tryParse(latStr);
                                if (lngStr != null) _dropLng = double.tryParse(lngStr);
                                if (_dropLat != null && _dropLng != null) {
                                  _saveRecentLocation(_dropLocation, _dropLat!, _dropLng!);
                                }
                                _scheduledDate = result['scheduledDate'] as String?;
                                _scheduledTime = result['scheduledTime'] as String?;
                                _rideState = 11;
                                _drawRoute();
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.search_rounded, color: Colors.grey.shade400, size: 20),
                                const SizedBox(width: 12),
                                Text('Where are you going?', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // OUR SERVICES
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text('OUR SERVICES', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildServiceIcon('Bike', Icons.pedal_bike_rounded, isPink, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerPassengerDetailsScreen(rideType: 'Bike')))),
                            _buildServiceIcon('Auto', Icons.electric_rickshaw_rounded, isPink, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerPassengerDetailsScreen(rideType: 'Auto')))),
                            _buildServiceIcon('EV car', Icons.local_taxi_rounded, isPink, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerPassengerDetailsScreen(rideType: 'EV Car')))),
                            _buildServiceIcon('7-seater', Icons.directions_car_filled_rounded, isPink, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerPassengerDetailsScreen(rideType: '7-seater')))),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Promo Banner
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ValueListenableBuilder<Map<String, dynamic>?>(
                          valueListenable: CustomerApp.activePromo,
                          builder: (context, activePromo, _) {
                            final isClaimed = activePromo != null && activePromo['title'] == '20% off your first ride';
                            return Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: promoBgColor,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('20% off your first ride', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text('Use code TORKK20 at checkout', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      if (!isClaimed) {
                                        CustomerApp.activePromo.value = {
                                          'title': '20% off your first ride',
                                          'type': 'percentage',
                                          'value': 20,
                                          'code': 'TORKK20',
                                        };
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Promo claimed!')));
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isClaimed ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(isClaimed ? 'Claimed' : 'Claim', style: TextStyle(color: isClaimed ? Colors.white : Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // RECENT TRIPS
                      if (_recentLocations.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text('RECENT TRIPS', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                        const SizedBox(height: 8),
                        for (var loc in _recentLocations)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _dropLocation = loc['name'] ?? '';
                                _dropLat = loc['lat'] as double?;
                                _dropLng = loc['lng'] as double?;
                                _rideState = 11; // Move to Select Vehicle state
                                _drawRoute();
                              });
                            },
                            child: Builder(
                              builder: (context) {
                                final dist = _currentPosition != null && loc['lat'] != null && loc['lng'] != null
                                  ? calculateDistance(_currentPosition!.latitude, _currentPosition!.longitude, loc['lat'] as double, loc['lng'] as double)
                                  : 5.0;
                                final fare = (79 + (dist * 12)).round();
                                return _buildRecentTripItem(
                                  isPink, 
                                  Icons.history_rounded, 
                                  '${_pickupLocation.split(',').isNotEmpty ? _pickupLocation.split(',')[0] : 'Current'} → ${loc['name']?.toString().split(',')[0] ?? ''}', 
                                  'Recently', 
                                  '₹$fare',
                                );
                              }
                            ),
                          ),
                      ],
                      
                      const SizedBox(height: 100), // padding for bottom nav
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceIcon(String title, IconData icon, bool isPink, VoidCallback onTap) {
    final bgColor = isPink ? const Color(0xFFFDE4F2) : const Color(0xFFE8F0FF);
    final iconColor = isPink ? const Color(0xFFEE4984) : const Color(0xFF295CFF);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _buildRecentTripItem(bool isPink, IconData icon, String title, String time, String price) {
    final bgColor = isPink ? const Color(0xFFFDE4F2) : const Color(0xFFE8F0FF);
    final iconColor = isPink ? const Color(0xFFEE4984) : const Color(0xFF295CFF);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Text(time, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Text(price, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(bool isPink) {
    final activeColor = isPink ? const Color(0xFFEE4984) : const Color(0xFF1E293B);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(Icons.home_filled, 'Home', true, activeColor, () {}),
          _buildNavItem(Icons.calendar_today_outlined, 'Schedule', false, Colors.grey.shade400, () async {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomerScheduleScreen()));
            if (result != null && result is Map<String, dynamic>) {
              setState(() {
                _pickupLocation = result['pickup'] as String? ?? 'Sector 45, Gurugram';
                _dropLocation = result['drop'] as String? ?? 'DLF Cyber City, Gurugram';
                final latStr = result['dropLat'] as String?;
                final lngStr = result['dropLng'] as String?;
                if (latStr != null) _dropLat = double.tryParse(latStr);
                if (lngStr != null) _dropLng = double.tryParse(lngStr);
                if (_dropLat != null && _dropLng != null) {
                  _saveRecentLocation(_dropLocation, _dropLat!, _dropLng!);
                }
                _scheduledDate = result['scheduledDate'] as String?;
                _scheduledTime = result['scheduledTime'] as String?;
                _rideState = 11;
                _drawRoute();
              });
            }
          }),
          _buildNavItem(Icons.account_balance_wallet_outlined, 'Wallet', false, Colors.grey.shade400, () {
            Navigator.pushNamed(context, '/ride-receipt');
          }),
          _buildNavItem(Icons.person_outline, 'Profile', false, Colors.grey.shade400, () {
            Navigator.pushNamed(context, '/profile');
          }),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive ? color : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isActive ? Colors.white : color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: isActive ? Colors.black87 : color, fontSize: 10, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? Colors.redAccent : Colors.white70),
      title: Text(
        title,
        style: TextStyle(color: isDestructive ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      ),
      onTap: onTap,
    );
  }

  // TOP BAR HEADER
  Widget _buildTopSearchHeader(Color primaryColor) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Builder(
          builder: (context) => ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu_rounded, color: Colors.black87),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.fiber_manual_record_rounded, color: Colors.green, size: 14),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _pickupLocation,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (_dropLocation.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, color: Colors.red, size: 14),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _dropLocation,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.history_rounded, color: primaryColor),
                      onPressed: () {
                        Navigator.pushNamed(context, '/history');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // BOTTOM PANEL STATE HANDLER
  Widget _buildStatePanel(Color primaryColor) {
    switch (_rideState) {
      case 10:
        return _buildStep10Dashboard(primaryColor);
      case 11:
        return _buildStep11SelectVehicle(primaryColor);
      // case 12: return _buildStep12OwnGender(primaryColor); // Old own-gender screen, commented out
      // case 25: return _buildStep25BiometricVerify(primaryColor); // Old per-ride face check, commented out
      case 13:
        return _buildStep13FareCalculation(primaryColor);
      case 14:
        return _buildStep14RideSettings(primaryColor);
      case 15:
        return _buildStep15ConfirmRide(primaryColor);
      case 16:
        return _buildStep16SearchingDriver(primaryColor);
      case 17:
        return _buildStep17DriverAccepted(primaryColor);
      case 18:
        return _buildStep18DriverArriving(primaryColor);
      case 19:
        return _buildStep19PickupConfirmed(primaryColor);
      case 20:
        return _buildStep20RideStarted(primaryColor);
      case 21:
        return _buildStep21LiveTracking(primaryColor);
      case 22:
        return _buildStep22DestinationReached(primaryColor);
      case 23:
        return _buildStep23RideCompleted(primaryColor);
      case 24:
        return _buildStep24RatingFeedback(primaryColor);
      default:
        return _buildStep10Dashboard(primaryColor);
    }
  }

  // STEP 10: DASHBOARD / SEARCH SELECTION
  Widget _buildStep10Dashboard(Color primaryColor) {
    return DraggableScrollableSheet(
      initialChildSize: 0.40,
      minChildSize: 0.40,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ListView(
              controller: scrollController,
              children: [
                Center(
                  child: Container(
                    width: 45,
                    height: 5,
                    margin: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                // Search Destination Button
                BouncingWidget(
                  onTap: () async {
                    final result = await Navigator.pushNamed(
                      context, 
                      '/search',
                      arguments: {
                        'pickup': _pickupLocation,
                        'drop': _dropLocation,
                        'pickupLat': _currentPosition?.latitude,
                        'pickupLng': _currentPosition?.longitude,
                      },
                    );
                    if (result != null && result is Map<String, dynamic>) {
                      setState(() {
                        _pickupLocation = result['pickup'] as String? ?? 'Sector 45, Gurugram';
                        _dropLocation = result['drop'] as String? ?? 'DLF Cyber City, Gurugram';
                        final latStr = result['dropLat'] as String?;
                        final lngStr = result['dropLng'] as String?;
                        if (latStr != null) _dropLat = double.tryParse(latStr);
                        if (lngStr != null) _dropLng = double.tryParse(lngStr);
                        if (_dropLat != null && _dropLng != null) {
                          _saveRecentLocation(_dropLocation, _dropLat!, _dropLng!);
                        }
                        _scheduledDate = result['scheduledDate'] as String?;
                        _scheduledTime = result['scheduledTime'] as String?;
                        _rideState = 11;
                        _drawRoute();
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: primaryColor, size: 24),
                        const SizedBox(width: 12),
                        Text('Where are you going?', style: TextStyle(fontSize: 16, color: Colors.blueGrey.shade600, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                


                if (_recentLocations.isNotEmpty) ...[
                  Text('RECENT LOCATIONS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.blueGrey.shade400, letterSpacing: 1.2)),
                  const SizedBox(height: 10),
                  for (var loc in _recentLocations)
                    _recentLocRow(loc['name'] ?? '', loc['subtitle'] ?? '', () {
                      setState(() {
                        _dropLocation = loc['name'] ?? '';
                        _dropLat = loc['lat'] as double?;
                        _dropLng = loc['lng'] as double?;
                        _rideState = 11;
                        _drawRoute();
                      });
                    }),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _quickAccessTile(IconData icon, String label, VoidCallback onTap, Color iconColor) {
    return BouncingWidget(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _recentLocRow(String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFF1F5F9),
        child: Icon(Icons.history_rounded, color: Colors.blueGrey),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black26),
      onTap: onTap,
    );
  }

  Widget _buildStep11SelectVehicle(Color primaryColor) {
    final List<Map<String, dynamic>> vehicles = [
      {'name': 'Bike', 'price': 120.0, 'eta': '2 mins', 'seats': '1 Passenger', 'maxSeats': 1, 'icon': Icons.directions_bike_rounded},
      {'name': 'Auto', 'price': 160.0, 'eta': '3 mins', 'seats': '3 Seats', 'maxSeats': 3, 'icon': Icons.local_taxi_rounded},
      {'name': 'Cab', 'price': 220.0, 'eta': '4 mins', 'seats': '4 Seats', 'maxSeats': 4, 'icon': Icons.directions_car_filled_rounded},
      {'name': 'EV Cab', 'price': 250.0, 'eta': '4 mins', 'seats': '4 Seats', 'maxSeats': 4, 'icon': Icons.electric_car_rounded},
      {'name': 'XL Cab', 'price': 320.0, 'eta': '5 mins', 'seats': '6 Seats', 'maxSeats': 6, 'icon': Icons.airport_shuttle_rounded},
    ];

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Select Vehicle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: _resetFlow),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: ListView.builder(
                itemCount: vehicles.length,
                itemBuilder: (context, index) {
                  final vehicle = vehicles[index];
                  final isSelected = _selectedVehicleName == vehicle['name'];
                  return Card(
                    color: isSelected ? primaryColor.withValues(alpha: 0.08) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: isSelected ? primaryColor : Colors.black12, width: isSelected ? 2 : 1),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Icon(vehicle['icon'], color: isSelected ? primaryColor : Colors.blueGrey, size: 28),
                      title: Text(vehicle['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('ETA: ${vehicle['eta']} • ${vehicle['seats']}'),
                      trailing: Text('₹${vehicle['price']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onTap: () {
                        setState(() {
                          _selectedVehicleName = vehicle['name'];
                          _selectedVehicle = vehicle['name'];
                          _selectedVehiclePrice = vehicle['price'];
                          _selectedVehicleMaxSeats = vehicle['maxSeats'];
                          _selectedVehicleIcon = vehicle['icon'];
                          
                          // Reset passengers when changing vehicle
                          if (_selectedVehicleName == 'Bike') {
                            _malePassengers = 1;
                            _femalePassengers = 0;
                          } else {
                            // Ensure passengers don't exceed max seats
                            int totalPassengers = _malePassengers + _femalePassengers;
                            if (totalPassengers > _selectedVehicleMaxSeats) {
                              _malePassengers = 1;
                              _femalePassengers = 0;
                            }
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // One-time face verification (done once ever, then hidden)
            if (!_faceVerifiedOnce)
              BouncingWidget(
                onTap: _faceVerifyBusy ? () {} : _startOneTimeFaceVerification,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Center(
                    child: _faceVerifyBusy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.face_retouching_natural_rounded, color: primaryColor, size: 20),
                              const SizedBox(width: 8),
                              const Text('Verify Face (One-Time)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_rounded, color: Colors.green.shade600, size: 20),
                    const SizedBox(width: 8),
                    Text('Face Verified', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),

            // Alternate gender toggle: OFF = ride books for your profile gender, ON = books for the alternate gender
            BouncingWidget(
              onTap: () {
                setState(() {
                  _alternateGenderMode = !_alternateGenderMode;
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _alternateGenderMode ? primaryColor.withValues(alpha: 0.1) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _alternateGenderMode ? primaryColor : Colors.grey.shade300,
                    width: _alternateGenderMode ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _alternateGenderLabel == 'Female' ? Icons.female : Icons.male,
                      color: _alternateGenderMode ? primaryColor : Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Book for $_alternateGenderLabel',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _alternateGenderMode ? primaryColor : Colors.grey.shade700,
                      ),
                    ),
                    if (_alternateGenderMode) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_circle_rounded, color: primaryColor, size: 18),
                    ],
                  ],
                ),
              ),
            ),

            BouncingWidget(
              onTap: () {
                if (!_faceVerifiedOnce) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please complete one-time face verification first')),
                  );
                  return;
                }
                setState(() {
                  if (_effectiveRideGender == 'Male') {
                    _malePassengers = 1;
                    _femalePassengers = 0;
                  } else {
                    _malePassengers = 0;
                    _femalePassengers = 1;
                  }
                  _rideState = 14; // Straight to Ride Settings; own-gender screen no longer used
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(16)),
                child: const Center(
                  child: Text('Confirm Vehicle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _startOneTimeFaceVerification() async {
    if (_faceVerifyBusy) return;
    setState(() => _faceVerifyBusy = true);
    try {
      final selfie = await _rideImagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
      );
      if (selfie == null) {
        setState(() => _faceVerifyBusy = false);
        return;
      }
      final bytes = await selfie.readAsBytes();
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';
      final response = await http.post(
        Uri.parse('$_baseUrl/api/kyc/verify-liveness'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'selfie_base64': base64Encode(bytes)}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (response.statusCode == 200 && data['status'] == 'success') {
        await prefs.setBool('face_verified_once', true);
        setState(() {
          _faceVerifiedOnce = true;
          _faceVerifyBusy = false;
        });
      } else {
        setState(() => _faceVerifyBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'Face verification failed')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _faceVerifyBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Face verification error: $e')));
    }
  }

  // ===== OLD SCREEN (commented out, replaced by the one-time face-verify + alternate-gender
  // buttons on the Select Vehicle screen above) =====
  // STEP 12: BOOKING PASSENGER'S OWN GENDER (universal, all vehicle types)
  /*
  Widget _buildStep12OwnGender(Color primaryColor) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Select Your Gender', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _rideState = 11)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: BouncingWidget(
                    onTap: () {
                      setState(() {
                        _ownGender = 'Male';
                        _malePassengers = 1;
                        _femalePassengers = 0;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _ownGender == 'Male' ? primaryColor : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _ownGender == 'Male' ? primaryColor : Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.male,
                            size: 40,
                            color: _ownGender == 'Male' ? Colors.white : Colors.grey.shade600,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Male',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _ownGender == 'Male' ? Colors.white : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: BouncingWidget(
                    onTap: () {
                      setState(() {
                        _ownGender = 'Female';
                        _malePassengers = 0;
                        _femalePassengers = 1;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _ownGender == 'Female' ? primaryColor : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _ownGender == 'Female' ? primaryColor : Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.female,
                            size: 40,
                            color: _ownGender == 'Female' ? Colors.white : Colors.grey.shade600,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Female',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _ownGender == 'Female' ? Colors.white : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            BouncingWidget(
              onTap: () => setState(() => _rideState = 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(16)),
                child: const Center(
                  child: Text('Continue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
  */

  Widget _passengerCounterRow(String label, int value, Function(int) onChange, Color primaryColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded),
              onPressed: () => onChange(-1),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
              child: Text('$value', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline_rounded, color: primaryColor),
              onPressed: () => onChange(1),
            ),
          ],
        )
      ],
    );
  }

  // ===== OLD SCREEN (commented out, replaced by the one-time face-verify button on the
  // Select Vehicle screen; ride confirmation no longer requires a face scan every time) =====
  // STEP 25: FACE LIVENESS CHECK (runs before every Confirm Ride)
  /*
  Future<void> _startFaceLiveness() async {
    if (_bioBusy) return;
    setState(() {
      _bioBusy = true;
      _bioError = null;
    });
    try {
      final XFile? selfie = await _rideImagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
      );
      if (selfie == null) {
        setState(() => _bioBusy = false);
        return;
      }
      final bytes = await selfie.readAsBytes();
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';
      final response = await http.post(
        Uri.parse('$_baseUrl/api/kyc/verify-liveness'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'selfie_base64': base64Encode(bytes)}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (response.statusCode == 200 && data['status'] == 'success') {
        setState(() {
          _bioBusy = false;
          _bioSubStep = 3;
        });
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) setState(() => _rideState = 15);
        });
      } else {
        setState(() {
          _bioBusy = false;
          _bioError = data['message']?.toString() ?? 'Face verification failed';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bioBusy = false;
        _bioError = 'Face verification error: $e';
      });
    }
  }

  Widget _buildStep25BiometricVerify(Color primaryColor) {
    final isPink = _ownGender == 'Female';
    final accent = isPink ? const Color(0xFFEC4899) : const Color(0xFF6366F1);

    final body = _bioSubStep == 3 ? _bioSuccessCard(accent) : _faceLivenessCard(accent);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: body,
      ),
    );
  }

  Widget _faceLivenessCard(Color accent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Verify it\'s really you', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _rideState = 14)),
          ],
        ),
        const SizedBox(height: 4),
        Text('One quick face scan to confirm you\'re a real person before every ride.', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 14)),
        const SizedBox(height: 24),
        Center(
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.08)),
            child: Icon(Icons.face_retouching_natural_rounded, size: 72, color: accent),
          ),
        ),
        const SizedBox(height: 16),
        if (_bioError != null)
          Center(
            child: Text(_bioError!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          ),
        const SizedBox(height: 20),
        BouncingWidget(
          onTap: _bioBusy ? () {} : _startFaceLiveness,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(16)),
            child: Center(
              child: _bioBusy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Start Face Scan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bioSuccessCard(Color accent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
        ),
        const SizedBox(height: 20),
        const Text('Identity verified', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Redirecting to confirm your ride...', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 14)),
        const SizedBox(height: 16),
      ],
    );
  }
  */

  // STEP 13: FARE CALCULATION LOADER
  Widget _buildStep13FareCalculation(Color primaryColor) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 2 * math.pi),
                  duration: const Duration(seconds: 2),
                  curve: Curves.linear,
                  builder: (context, value, child) {
                    return Transform.rotate(
                      angle: value,
                      child: Icon(Icons.currency_rupee_rounded, size: 48, color: primaryColor),
                    );
                  },
                ),
                const SizedBox(height: 20),
                const Text('Calculating Fare...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                const Text('Please wait...', style: TextStyle(color: Colors.black54, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // STEP 14: RIDE SETTINGS (passenger count, driver-gender preview, offers/coupon, Proceed to Calculate Fare)
  Widget _buildStep14RideSettings(Color primaryColor) {
    final isPink = CustomerApp.isPinkTheme.value;
    final appliedPromo = CustomerApp.activePromo.value;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_selectedVehicleName.toUpperCase()} Ride Settings', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _rideState = 12)),
              ],
            ),
            const SizedBox(height: 16),

            _passengerCounterRow('Male Passengers', _malePassengers, (val) {
              setState(() {
                int newMale = math.max(0, _malePassengers + val);
                int totalPassengers = newMale + _femalePassengers;
                if (totalPassengers <= _selectedVehicleMaxSeats) {
                  _malePassengers = newMale;
                }
              });
            }, primaryColor),
            const SizedBox(height: 16),
            _passengerCounterRow('Female Passengers', _femalePassengers, (val) {
              setState(() {
                int newFemale = math.max(0, _femalePassengers + val);
                int totalPassengers = _malePassengers + newFemale;
                if (totalPassengers <= _selectedVehicleMaxSeats) {
                  _femalePassengers = newFemale;
                }
              });
            }, primaryColor),
            const SizedBox(height: 12),

            // Max seats info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Max $_selectedVehicleMaxSeats passengers • Currently: ${_malePassengers + _femalePassengers}',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Driver-gender preview, derived from majority of passenger genders
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(_derivedDriverGender == 'Female' ? Icons.female : Icons.male, color: primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Driver will be $_derivedDriverGender',
                    style: TextStyle(fontSize: 12, color: primaryColor, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Discount / Offers chip
            GestureDetector(
              onTap: () => _showOffersSheet(primaryColor, isPink),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: appliedPromo != null ? Colors.green.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: appliedPromo != null ? Colors.green : Colors.black12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_offer, color: appliedPromo != null ? Colors.green : primaryColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        appliedPromo != null ? '${appliedPromo['code']} applied' : 'Discount',
                        style: TextStyle(fontWeight: FontWeight.bold, color: appliedPromo != null ? Colors.green : Colors.black87),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            BouncingWidget(
              onTap: () {
                int totalPassengers = _malePassengers + _femalePassengers;
                if (totalPassengers == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select at least 1 passenger'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                if (totalPassengers > _selectedVehicleMaxSeats) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Maximum $_selectedVehicleMaxSeats passengers allowed for $_selectedVehicleName'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                _estimateRide();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(16)),
                child: const Center(
                  child: Text('Proceed to Calculate Fare', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showOffersSheet(Color primaryColor, bool isPink) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 24),
                  const Text('Offers and coupons', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 24),
                  const Text('AVAILABLE OFFERS', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        _buildOfferItem(setModalState, 'TORKK20', '20% off your first ride', 'Up to ₹60', primaryColor, isPink, {'title': '20% off your first ride', 'type': 'percentage', 'value': 20, 'code': 'TORKK20', 'max': 60}),
                        const SizedBox(height: 12),
                        _buildOfferItem(setModalState, 'EVSAVE50', 'Flat ₹50 off on EV rides', 'Min fare ₹120', primaryColor, isPink, {'title': 'Flat ₹50 off on EV rides', 'type': 'flat', 'value': 50, 'code': 'EVSAVE50', 'condition': 'EV Cab'}),
                        const SizedBox(height: 12),
                        _buildOfferItem(setModalState, 'WEEKEND15', '15% off weekend rides', 'Sat-Sun only', primaryColor, isPink, {'title': '15% off weekend rides', 'type': 'percentage', 'value': 15, 'code': 'WEEKEND15'}),
                      ],
                    ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildOfferItem(StateSetter setModalState, String code, String title, String sub, Color primaryColor, bool isPink, Map<String, dynamic> promoData) {
    bool isApplied = CustomerApp.activePromo.value != null && CustomerApp.activePromo.value!['code'] == code;
    return GestureDetector(
      onTap: () {
        setModalState(() {
          CustomerApp.activePromo.value = isApplied ? null : promoData;
        });
        setState(() {}); // Update parent
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isApplied ? (isPink ? const Color(0xFFFDF2F8) : const Color(0xFFEFF6FF)) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isApplied ? primaryColor : Colors.grey.shade200, style: isApplied ? BorderStyle.solid : BorderStyle.none),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: isApplied ? primaryColor : primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.local_offer, color: isApplied ? Colors.white : primaryColor, size: 20),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: isApplied ? primaryColor.withValues(alpha: 0.2) : Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                      child: Text(code, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: isApplied ? primaryColor : Colors.black87)),
                    ),
                    const SizedBox(height: 4),
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(sub, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ],
            ),
            Text(isApplied ? 'APPLIED' : 'APPLY', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // STEP 15: CONFIRM RIDE SUMMARY
  Widget _buildStep15ConfirmRide(Color primaryColor) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Confirm Ride Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: _resetFlow),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black12)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(_selectedVehicleIcon, color: primaryColor),
                          const SizedBox(width: 10),
                          Text(_selectedVehicleName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text('Passengers: ${_malePassengers + _femalePassengers}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.fiber_manual_record_rounded, color: Colors.green, size: 14),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_pickupLocation, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_rounded, color: Colors.red, size: 14),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_dropLocation, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                    ],
                  ),
                  const Divider(height: 24),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Distance / Time', style: TextStyle(color: Colors.black54, fontSize: 13)),
                      Text('12.4 km | 28 mins', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Fare', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('₹${_selectedVehiclePrice.toInt()}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: primaryColor)),
              ],
            ),
            const SizedBox(height: 20),

            BouncingWidget(
              onTap: () {
                if (_scheduledDate != null) {
                  _showScheduledPaymentAndConfirm(primaryColor);
                } else {
                  _requestRide();
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(16)),
                child: Center(
                  child: Text(_scheduledDate != null ? 'SCHEDULE RIDE' : 'Confirm Ride', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // Scheduled-ride path: a mock payment sheet followed by a "Ride Scheduled!" confirmation.
  // No real backend ride-request call for scheduled rides (matches the original mock behavior).
  void _showScheduledPaymentAndConfirm(Color primaryColor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool isProcessing = false;
        int selectedPaymentIndex = 0; // 0 = Wallet, 1 = UPI, 2 = Card
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.55,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: isProcessing
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: primaryColor),
                        const SizedBox(height: 16),
                        Text(selectedPaymentIndex == 0 ? 'Processing Payment...' : 'Verifying with Razorpay...', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                        const SizedBox(height: 24),
                        const Text('Payment Gateway', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF0F172A))),
                        const SizedBox(height: 8),
                        Text('Pay ₹${_selectedVehiclePrice.round()} to schedule your ride', style: TextStyle(color: Colors.grey.shade500)),
                        const SizedBox(height: 32),
                        GestureDetector(
                          onTap: () => setSheetState(() => selectedPaymentIndex = 0),
                          child: _buildPaymentMethodTile(Icons.account_balance_wallet, 'Torkk Wallet', 'Balance: ₹500', primaryColor, selectedPaymentIndex == 0),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () => setSheetState(() => selectedPaymentIndex = 1),
                          child: _buildPaymentMethodTile(Icons.account_balance, 'UPI / Net Banking', 'Google Pay, PhonePe, etc', primaryColor, selectedPaymentIndex == 1),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () => setSheetState(() => selectedPaymentIndex = 2),
                          child: _buildPaymentMethodTile(Icons.credit_card, 'Credit / Debit Card', 'Visa, Mastercard', primaryColor, selectedPaymentIndex == 2),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            setSheetState(() => isProcessing = true);
                            Future.delayed(const Duration(seconds: 2), () {
                              Navigator.pop(ctx); // close payment sheet
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (dialogCtx) => Dialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(28),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                                          child: Icon(Icons.check_circle_rounded, color: primaryColor, size: 48),
                                        ),
                                        const SizedBox(height: 20),
                                        const Text('Ride Scheduled!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF0F172A))),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Your $_selectedVehicleName ride has been booked for $_scheduledDate at $_scheduledTime.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13, height: 1.5),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Total Paid: ₹${_selectedVehiclePrice.round()}',
                                          style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 24),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                                          child: Column(
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(Icons.fiber_manual_record, color: primaryColor, size: 10),
                                                  const SizedBox(width: 8),
                                                  Expanded(child: Text(_pickupLocation.split(',').first, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                                                ],
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                                child: Container(height: 20, width: 1, color: Colors.grey.shade300),
                                              ),
                                              Row(
                                                children: [
                                                  const Icon(Icons.square, color: Color(0xFF0F172A), size: 10),
                                                  const SizedBox(width: 8),
                                                  Expanded(child: Text(_dropLocation.split(',').first, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        GestureDetector(
                                          onTap: () {
                                            Navigator.of(dialogCtx).pop();
                                            _resetFlow();
                                          },
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(vertical: 16),
                                            decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(14)),
                                            child: const Center(child: Text('Back to Home', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            });
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(14)),
                            child: const Center(child: Text('Pay Securely', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                          ),
                        ),
                      ],
                    ),
                  ),
          );
        });
      },
    );
  }

  Widget _buildPaymentMethodTile(IconData icon, String title, String subtitle, Color primaryColor, bool isSelected) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected ? primaryColor.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSelected ? primaryColor : Colors.black12, width: isSelected ? 2 : 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: isSelected ? primaryColor : Colors.black54),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          ),
          if (isSelected) Icon(Icons.check_circle_rounded, color: primaryColor)
        ],
      ),
    );
  }

  // STEP 16: SEARCHING DRIVER PULSE
  Widget _buildStep16SearchingDriver(Color primaryColor) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulse Radar Simulation
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryColor.withValues(alpha: 0.1),
                      ),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(seconds: 2),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Container(
                          width: 90 + 60 * value,
                          height: 90 + 60 * value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: primaryColor.withValues(alpha: 1.0 - value), width: 2),
                          ),
                        );
                      },
                    ),
                    Icon(Icons.directions_car_filled_rounded, size: 40, color: primaryColor),
                  ],
                ),
                const SizedBox(height: 32),
                const Text('Searching Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 8),
                const Text('Searching for nearby drivers...', style: TextStyle(color: Colors.black54, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // STEP 17: DRIVER ACCEPTED
  Widget _buildStep17DriverAccepted(Color primaryColor) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text('Driver has accepted your ride', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
                  child: Icon(Icons.person_rounded, size: 36, color: primaryColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_driverName ?? 'Driver', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text((_driverRating ?? 4.8).toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                      child: Text(_driverPlateNumber ?? 'HR55AB1234', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const SizedBox(height: 4),
                    Text(_driverVehicleModel ?? 'White Sedan', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                )
              ],
            ),
            const SizedBox(height: 16),
            BouncingWidget(
              onTap: () {
                setState(() {
                  _rideState = 18; // Driver Arriving
                  _triggerStateAction();
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(16)),
                child: const Center(
                  child: Text('Track Driver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _openShareTripStatus() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShareTripStatusScreen(
          pickupName: _pickupLocation,
          dropName: _dropLocation,
          customerName: _userName,
          distanceKm: _estimatedDistance,
          totalFare: _selectedVehiclePrice.round(),
          driverName: _driverName ?? 'Driver',
          driverVehicle: '${_driverVehicleModel ?? "Vehicle"} · ${_driverPlateNumber ?? ""}',
          driverType: '$_derivedDriverGender driver',
        ),
      ),
    );
  }

  // STEP 18: DRIVER ARRIVING (3 MINS ETA)
  Widget _buildStep18DriverArriving(Color primaryColor) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.navigation_rounded, color: primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Driver is on the way', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${_driverName ?? 'Driver'} • ${_driverVehicleModel ?? 'White Sedan'} (${_driverPlateNumber ?? 'HR55AB1234'})', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: [
                      Text('ETA', style: TextStyle(fontSize: 10, color: primaryColor, fontWeight: FontWeight.bold)),
                      Text('3 mins', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text('Share this code with your driver at pickup', style: TextStyle(fontSize: 12, color: primaryColor, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    _pickupOtp ?? '----',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8, color: primaryColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            BouncingWidget(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Dialing driver at ${_driverPhone ?? '9876543210'}...')),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(border: Border.all(color: primaryColor, width: 2), borderRadius: BorderRadius.circular(16)),
                child: Center(
                  child: Text('Call Driver', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // STEP 19: PICKUP CONFIRMED
  Widget _buildStep19PickupConfirmed(Color primaryColor) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 72),
                const SizedBox(height: 20),
                const Text('PICKUP CONFIRMED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF1E293B))),
                const SizedBox(height: 6),
                const Text('Enjoy your ride!', style: TextStyle(color: Colors.black54, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // STEP 20: RIDE STARTED
  Widget _buildStep20RideStarted(Color primaryColor) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.directions_car_rounded, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ride Started!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Heading safely to your destination', style: TextStyle(color: Colors.black54, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // STEP 21: LIVE TRACKING
  Widget _buildStep21LiveTracking(Color primaryColor) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.location_searching_rounded, color: Colors.blue, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Live Tracking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Sharing location in real time', style: TextStyle(color: Colors.black54, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.share_rounded, color: primaryColor),
                  onPressed: _shareLiveLocation,
                ),
                IconButton(
                  icon: const Icon(Icons.sos_rounded, color: Colors.red),
                  onPressed: _triggerSOS,
                )
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _shareLiveLocation() {
    final lat = _driverLat ?? _currentPosition?.latitude;
    final lng = _driverLng ?? _currentPosition?.longitude;
    final mapsLink = (lat != null && lng != null) ? 'https://maps.google.com/?q=$lat,$lng' : '';
    final message = StringBuffer()
      ..writeln("I'm on a Torkk ride, tracking my trip live:")
      ..writeln('Pickup: $_pickupLocation')
      ..writeln('Drop: $_dropLocation')
      ..writeln('Driver: ${_driverName ?? "Driver"} · ${_driverPlateNumber ?? ""}');
    if (mapsLink.isNotEmpty) {
      message.writeln('Live location: $mapsLink');
    }
    SharePlus.instance.share(ShareParams(text: message.toString()));
  }

  // STEP 22: DESTINATION REACHED
  Widget _buildStep22DestinationReached(Color primaryColor) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flag_rounded, size: 64, color: primaryColor),
                const SizedBox(height: 20),
                const Text('DESTINATION REACHED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 6),
                const Text('You have safely arrived!', style: TextStyle(color: Colors.black54, fontSize: 14)),
                const SizedBox(height: 24),
                BouncingWidget(
                  onTap: _startRazorpayPayment,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(12)),
                    child: const Text('Pay Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  // STEP 23: RIDE COMPLETED
  Widget _buildStep23RideCompleted(Color primaryColor) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 54),
            const SizedBox(height: 14),
            const Text('Ride Completed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Fare Paid', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('₹${_selectedVehiclePrice.toInt()}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('Paid automatically via Wallet', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 24),
            BouncingWidget(
              onTap: () => setState(() => _rideState = 24),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(16)),
                child: const Center(
                  child: Text('Rate Your Ride', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // STEP 24: RATING & FEEDBACK
  Widget _buildStep24RatingFeedback(Color primaryColor) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('How was your ride?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            // Star selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final isLit = index < _starRating;
                return IconButton(
                  icon: Icon(
                    isLit ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: Colors.amber,
                    size: 40,
                  ),
                  onPressed: () {
                    setState(() {
                      _starRating = index + 1.0;
                    });
                  },
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                hintText: 'Write your feedback (optional)',
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor)),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            BouncingWidget(
              onTap: () => _showSafetyConfirmationPopup(primaryColor),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(16)),
                child: const Center(
                  child: Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // SAFETY CONFIRMATION DIALOG
  void _showSafetyConfirmationPopup(Color primaryColor) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Center(
          child: Text('Safety Confirmation', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Did you safely reach your destination?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          // No Button
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red, width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(context);
              _showSafetySupportOverlay(primaryColor);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                SizedBox(width: 6),
                Text('No, I need help', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Yes Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(context);
              _showThankYouOverlay();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 18),
                SizedBox(width: 6),
                Text('Yes, I reached safely', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // THANK YOU OVERLAY
  void _showThankYouOverlay() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sentiment_very_satisfied_rounded, color: Colors.green, size: 64),
              const SizedBox(height: 20),
              const Text('Thank You!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Have a safe day ahead.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _resetFlow();
                },
                child: const Text('Back to Dashboard'),
              )
            ],
          ),
        ),
      ),
    );
  }



  void _showEmergencyContactsDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isLoading = true;
        final List<TextEditingController> nameControllers = List.generate(3, (_) => TextEditingController());
        final List<TextEditingController> phoneControllers = List.generate(3, (_) => TextEditingController());

        return StatefulBuilder(
          builder: (context, setState) {
            if (isLoading && nameControllers[0].text.isEmpty && phoneControllers[0].text.isEmpty) {
              UserService.getEmergencyContacts(phone).then((loadedContacts) {
                for (int i = 0; i < loadedContacts.length && i < 3; i++) {
                  nameControllers[i].text = loadedContacts[i]['name'] ?? '';
                  phoneControllers[i].text = loadedContacts[i]['phone'] ?? '';
                }
                if (mounted) setState(() => isLoading = false);
              }).catchError((e) {
                if (mounted) setState(() => isLoading = false);
              });
            }

            return AlertDialog(
              title: const Text('Emergency Contacts'),
              content: isLoading
                  ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(3, (index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Contact ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                                TextField(
                                  controller: nameControllers[index],
                                  decoration: const InputDecoration(labelText: 'Name', isDense: true),
                                ),
                                TextField(
                                  controller: phoneControllers[index],
                                  decoration: const InputDecoration(labelText: 'Phone Number', isDense: true),
                                  keyboardType: TextInputType.phone,
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    setState(() => isLoading = true);
                    List<Map<String, String>> toSave = [];
                    for (int i = 0; i < 3; i++) {
                      if (nameControllers[i].text.trim().isNotEmpty && phoneControllers[i].text.trim().isNotEmpty) {
                        toSave.add({
                          'name': nameControllers[i].text.trim(),
                          'phone': phoneControllers[i].text.trim(),
                        });
                      }
                    }
                    try {
                      await UserService.saveEmergencyContacts(phone, toSave);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contacts saved successfully!')));
                      }
                    } catch (e) {
                      if (mounted) setState(() => isLoading = false);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // SAFETY SUPPORT SCREEN / OVERLAY
  void _showSafetySupportOverlay(Color primaryColor) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Safety Support',
      pageBuilder: (context, anim1, anim2) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Safety Support'),
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: Colors.red, size: 36),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SAFETY IS OUR PRIORITY', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)),
                            Text('Torkk is with you, always!', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                _safetyActionCard(Icons.emergency_share_rounded, 'SOS Emergency', 'Instantly trigger emergency protocol', () {
                  _triggerSOS();
                  showDialog(
                    context: context,
                    builder: (context) => const AlertDialog(
                      title: Text('🚨 SOS Alert Triggered'),
                      content: Text('Immediate dispatch of safety officers and alerts to emergency contacts initiated.'),
                    ),
                  );
                }, Colors.red),
                
                const SizedBox(height: 16),
                _safetyActionCard(Icons.phone_in_talk_rounded, 'Call Support (24x7)', 'Connect directly to Torkk Helpline', () {}, primaryColor),
                
                const SizedBox(height: 16),
                _safetyActionCard(Icons.contacts_rounded, 'Emergency Contacts', 'Notify pre-saved emergency contacts', () {
                  _showEmergencyContactsDialog();
                }, primaryColor),
                
                const Spacer(),
                CustomButton(
                  text: 'Close & Reset Dashboard',
                  onTap: () {
                    Navigator.pop(context);
                    _resetFlow();
                  },
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _safetyActionCard(IconData icon, String title, String subtitle, VoidCallback onTap, Color themeColor) {
    return BouncingWidget(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: themeColor.withValues(alpha: 0.1),
              child: Icon(icon, color: themeColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}

// --- UPGRADED MOCK MAP PAINTER ---
class MockMapPainter extends CustomPainter {
  final double animationValue;
  final bool isPinkTheme;
  final int rideState;
  final double progressValue;

  MockMapPainter({
    required this.animationValue,
    required this.isPinkTheme,
    required this.rideState,
    required this.progressValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final activeColor = isPinkTheme ? const Color(0xFFEC4899) : const Color(0xFF6366F1);

    // 1. Draw Land background
    final paintLand = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintLand);

    // 2. Draw Park zones
    final paintPark = Paint()..color = const Color(0xFFDCFCE7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(40, 120, 160, 200), const Radius.circular(24)),
      paintPark,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(size.width - 180, 350, 150, 250), const Radius.circular(24)),
      paintPark,
    );

    // 3. Draw River
    final paintWater = Paint()
      ..color = const Color(0xFFE0F2FE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 35
      ..strokeCap = StrokeCap.round;
    final pathWater = Path();
    pathWater.moveTo(-20, size.height * 0.7);
    pathWater.quadraticBezierTo(size.width * 0.3, size.height * 0.75, size.width * 0.6, size.height * 0.65);
    pathWater.quadraticBezierTo(size.width * 0.85, size.height * 0.55, size.width + 20, size.height * 0.6);
    canvas.drawPath(pathWater, paintWater);

    // 4. Draw main road lines
    final paintRoadBorder = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;

    final paintRoad = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    final List<Path> roads = [];
    
    // Vertical road
    final road1 = Path();
    road1.moveTo(size.width * 0.45, -20);
    road1.lineTo(size.width * 0.45, size.height + 20);
    roads.add(road1);

    // Horizontal road
    final road2 = Path();
    road2.moveTo(-20, size.height * 0.36);
    road2.lineTo(size.width + 20, size.height * 0.36);
    roads.add(road2);

    // Diagonal road
    final road3 = Path();
    road3.moveTo(size.width * 0.8, -20);
    road3.lineTo(size.width * 0.2, size.height + 20);
    roads.add(road3);

    for (var r in roads) {
      canvas.drawPath(r, paintRoadBorder);
    }
    for (var r in roads) {
      canvas.drawPath(r, paintRoad);
    }

    // Coordinates for simulation
    final pickupPin = Offset(size.width * 0.45, size.height * 0.36);
    final driverStart = Offset(size.width * 0.7, size.height * 0.12);
    final dropPin = Offset(size.width * 0.25, size.height * 0.75);

    // 5. Draw active routes / matching state path lines
    if (rideState >= 15 && rideState <= 22) {
      // Draw solid route path line from Pickup to Dropoff
      final paintRouteLine = Paint()
        ..color = activeColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(pickupPin, dropPin, paintRouteLine);
    }

    if (rideState == 18) {
      // Driver Arriving: Draw dotted route from Driver Start to Pickup
      final paintDriverPath = Paint()
        ..color = Colors.amber.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      
      // Simulating a simple dashed line
      final double dx = pickupPin.dx - driverStart.dx;
      final double dy = pickupPin.dy - driverStart.dy;
      for (double i = 0.0; i <= 1.0; i += 0.1) {
        canvas.drawCircle(Offset(driverStart.dx + dx * i, driverStart.dy + dy * i), 4, paintDriverPath);
      }
    }

    // 6. Draw Pickup Pin (Green)
    final paintPickup = Paint()..color = Colors.green;
    canvas.drawCircle(pickupPin, 8, paintPickup);
    canvas.drawCircle(pickupPin, 14, Paint()..color = Colors.green.withValues(alpha: 0.15));

    // 7. Draw Drop Pin (Red) if active
    if (rideState >= 11) {
      final paintDrop = Paint()..color = Colors.red;
      canvas.drawCircle(dropPin, 8, paintDrop);
      canvas.drawCircle(dropPin, 14, Paint()..color = Colors.red.withValues(alpha: 0.15));
    }

    // 8. Draw moving vehicles according to simulation progress
    Offset? carPos;
    Color carColor = const Color(0xFFFBBF24); // Yellow

    if (rideState == 18) {
      // Driver arriving: move from driverStart to pickupPin
      final double dx = pickupPin.dx - driverStart.dx;
      final double dy = pickupPin.dy - driverStart.dy;
      carPos = Offset(driverStart.dx + dx * progressValue, driverStart.dy + dy * progressValue);
    } else if (rideState == 20 || rideState == 21) {
      // Ride ongoing: move from pickupPin to dropPin
      final double dx = dropPin.dx - pickupPin.dx;
      final double dy = dropPin.dy - pickupPin.dy;
      carPos = Offset(pickupPin.dx + dx * progressValue, pickupPin.dy + dy * progressValue);
      carColor = activeColor; // Changes to theme color during active trip!
    } else if (rideState >= 10 && rideState <= 17) {
      // Static background ambient cabs
      carPos = Offset(size.width * 0.45, 100 + (size.height * 0.4) * animationValue);
    }

    if (carPos != null) {
      final paintCar = Paint()
        ..color = carColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: carPos, width: 20, height: 28), const Radius.circular(6)), paintCar);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: carPos, width: 20, height: 28), const Radius.circular(6)), Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 1.5);
      // Windshield
      canvas.drawRect(Rect.fromLTWH(carPos.dx - 7, carPos.dy - 9, 14, 4), Paint()..color = Colors.black87);
    }
  }

  @override
  bool shouldRepaint(covariant MockMapPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.rideState != rideState ||
        oldDelegate.progressValue != progressValue;
  }
}

// --- Standalone auxiliary pages requested by routes ---

double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371.0;
  final dLat = (lat2 - lat1) * (math.pi / 180.0);
  final dLon = (lon2 - lon1) * (math.pi / 180.0);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * (math.pi / 180.0)) * math.cos(lat2 * (math.pi / 180.0)) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

class CustomerSearchScreen extends StatefulWidget {
  final String? scheduledDate;
  final String? scheduledTime;
  const CustomerSearchScreen({super.key, this.scheduledDate, this.scheduledTime});

  @override
  State<CustomerSearchScreen> createState() => _CustomerSearchScreenState();
}

class _CustomerSearchScreenState extends State<CustomerSearchScreen> {
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  bool _initialized = false;
  
  double? _pickupLat;
  double? _pickupLng;
  double? _dropLat;
  double? _dropLng;
  String? _currentCity;
  String? _currentState;

  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _pickupController.text = args['pickup'] ?? 'Sector 45, Gurugram';
        _dropController.text = args['drop'] ?? 'DLF Cyber City, Gurugram';
        _pickupLat = args['pickupLat'];
        _pickupLng = args['pickupLng'];

        if (_pickupController.text != 'Current Location') {
           final parts = _pickupController.text.split(',');
           if (parts.length >= 2) {
             _currentCity = parts[0].trim().toLowerCase();
             _currentState = parts[1].trim().toLowerCase();
           }
        }
      } else {
        _pickupController.text = 'Sector 45, Gurugram';
        _dropController.text = 'DLF Cyber City, Gurugram';
      }
      _initialized = true;
    }
  }

  Future<void> _fetchNominatim(String query, bool bounded) async {
    String urlStr = 'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=15&countrycodes=in';
    if (bounded && _pickupLat != null && _pickupLng != null) {
      final delta = 0.4;
      final left = _pickupLng! - delta;
      final right = _pickupLng! + delta;
      final top = _pickupLat! + delta;
      final bottom = _pickupLat! - delta;
      urlStr += '&viewbox=$left,$top,$right,$bottom&bounded=1';
    }

    try {
      final response = await http.get(Uri.parse(urlStr), headers: {'User-Agent': 'TorkkApp/1.0'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        List<Map<String, dynamic>> results = [];
        
        for (var e in data) {
          final lat = double.tryParse(e['lat']?.toString() ?? '0') ?? 0.0;
          final lon = double.tryParse(e['lon']?.toString() ?? '0') ?? 0.0;
          final dist = (_pickupLat != null && _pickupLng != null) 
              ? calculateDistance(_pickupLat!, _pickupLng!, lat, lon)
              : 0.0;
          
          if (_pickupLat != null && _pickupLng != null && dist > 50.0) {
              continue;
          }

          results.add({
              'name': e['display_name'].toString(),
              'distance': dist,
              'lat': lat,
              'lon': lon,
          });
        }
        
        results.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
        
        if (mounted) {
          setState(() {
            _suggestions = results;
          });
          
          if (results.isEmpty && bounded) {
            _fetchNominatim(query, false);
          } else {
            setState(() => _isLoading = false);
          }
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Search error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.length < 3) {
      setState(() {
        _suggestions = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() => _isLoading = true);
      _fetchNominatim(query, true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupController.dispose();
    _dropController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPink = CustomerApp.isPinkTheme.value;
    final primaryColor = isPink ? const Color(0xFFEC4899) : const Color(0xFF6366F1);

    return Scaffold(
      appBar: AppBar(title: const Text('Search Destination')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Scheduled banner
            if (widget.scheduledDate != null) ...[  
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: primaryColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 13),
                          children: [
                            TextSpan(text: 'Scheduled: ', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                            TextSpan(text: '${widget.scheduledDate} at ${widget.scheduledTime}', style: const TextStyle(color: Color(0xFF0F172A))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            CustomTextField(labelText: 'Pickup Location', controller: _pickupController),
            const SizedBox(height: 16),
            CustomTextField(
              labelText: 'Dropoff Location', 
              controller: _dropController,
              onChanged: _onSearchChanged,
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 16.0),
                child: CircularProgressIndicator(),
              ),
            if (_suggestions.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    final name = suggestion['name'] as String;
                    final distance = suggestion['distance'] as double;
                    final lat = suggestion['lat'] as double;
                    final lon = suggestion['lon'] as double;
                    return ListTile(
                      leading: const Icon(Icons.location_on, color: Colors.red),
                      title: Text(name),
                      subtitle: distance > 0 ? Text('${distance.toStringAsFixed(1)} km away') : null,
                      onTap: () {
                        setState(() {
                          _dropController.text = name;
                          _dropLat = lat;
                          _dropLng = lon;
                          _suggestions = []; // Clear after selecting
                        });
                      },
                    );
                  },
                ),
              ),
            if (_suggestions.isEmpty)
               const SizedBox(height: 32),
            if (_suggestions.isEmpty)
              CustomButton(
                text: 'Find Vehicles',
                color: primaryColor,
                onTap: () {
                  if (_pickupController.text.isNotEmpty && _dropController.text.isNotEmpty) {
                    // Hand pickup/drop (and schedule, if any) straight back to the dashboard's
                    // real ride-booking flow (_rideState machine) instead of the old
                    // "Confirm Your Ride" page, which never actually called the backend.
                    Navigator.pop(context, {
                      'pickup': _pickupController.text,
                      'drop': _dropController.text,
                      'dropLat': _dropLat?.toString(),
                      'dropLng': _dropLng?.toString(),
                      'scheduledDate': widget.scheduledDate,
                      'scheduledTime': widget.scheduledTime,
                    });
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class CustomerBookingScreen extends StatelessWidget {
  const CustomerBookingScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Use dashboard flow')));
}

class CustomerTrackingScreen extends StatelessWidget {
  const CustomerTrackingScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Use dashboard flow')));
}

class CustomerPaymentScreen extends StatelessWidget {
  const CustomerPaymentScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Use dashboard flow')));
}

// ============================================
// SHARE TRIP STATUS SCREEN
// ============================================
class ShareTripStatusScreen extends StatefulWidget {
  final String pickupName;
  final String dropName;
  final String customerName;
  final double distanceKm;
  final int totalFare;
  final String driverName;
  final String driverVehicle;
  final String driverType;

  const ShareTripStatusScreen({
    super.key,
    required this.pickupName,
    required this.dropName,
    required this.customerName,
    required this.distanceKm,
    required this.totalFare,
    required this.driverName,
    required this.driverVehicle,
    required this.driverType,
  });

  @override
  State<ShareTripStatusScreen> createState() => _ShareTripStatusScreenState();
}

class _ShareTripStatusScreenState extends State<ShareTripStatusScreen> {
  final List<Map<String, dynamic>> _contacts = [];
  final Set<int> _selectedContacts = {};
  bool _loadingContacts = true;
  Position? _currentPosition;
  GoogleMapController? _mapController;
  bool _isSharing = false;

  String get _driverInitials {
    final parts = widget.driverName.split(' ');
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return widget.driverName.isNotEmpty ? widget.driverName.substring(0, math.min(2, widget.driverName.length)).toUpperCase() : 'DR';
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentPosition();
    _loadContacts();
  }

  Future<void> _loadCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentPosition = pos);
    } catch (_) {}
  }

  Future<void> _loadContacts() async {
    try {
      // Request contacts permission
      if (await FlutterContacts.requestPermission()) {
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        if (mounted) {
          setState(() {
            _contacts.addAll(contacts.take(10).map((c) {
              final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
              final name = c.displayName;
              final initials = name.isNotEmpty
                  ? (name.split(' ').length > 1
                      ? '${name[0]}${name.split(' ')[1][0]}'.toUpperCase()
                      : name.substring(0, math.min(2, name.length)).toUpperCase())
                  : 'XX';
              return {'name': name, 'phone': phone, 'initials': initials};
            }).toList());
            // Pre-select first 2 contacts
            if (_contacts.length >= 2) {
              _selectedContacts.addAll([0, 1]);
            }
            _loadingContacts = false;
          });
        }
      } else {
        // Fallback mock contacts
        if (mounted) {
          setState(() {
            _contacts.addAll([
              {'name': 'Anjali Rao', 'phone': '+91 98XXX XX210', 'initials': 'AR', 'relation': 'Mother'},
              {'name': 'Divya Nair', 'phone': '+91 99XXX XX045', 'initials': 'DN', 'relation': 'Best friend'},
              {'name': 'Kavya Iyer', 'phone': '+91 97XXX XX083', 'initials': 'KI', 'relation': 'Sister'},
            ]);
            _selectedContacts.addAll([0, 1]);
            _loadingContacts = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _contacts.addAll([
            {'name': 'Anjali Rao', 'phone': '+91 98XXX XX210', 'initials': 'AR', 'relation': 'Mother'},
            {'name': 'Divya Nair', 'phone': '+91 99XXX XX045', 'initials': 'DN', 'relation': 'Best friend'},
            {'name': 'Kavya Iyer', 'phone': '+91 97XXX XX083', 'initials': 'KI', 'relation': 'Sister'},
          ]);
          _selectedContacts.addAll([0, 1]);
          _loadingContacts = false;
        });
      }
    }
  }

  String _buildShareMessage() {
    final lat = _currentPosition?.latitude.toStringAsFixed(6) ?? '28.6139';
    final lng = _currentPosition?.longitude.toStringAsFixed(6) ?? '77.2090';
    return '🚖 ${widget.customerName} is on a Torkk ride!\n\n'
        '📍 Pickup: ${widget.pickupName}\n'
        '🏁 Drop: ${widget.dropName}\n'
        '🚗 Driver: ${widget.driverName} · ${widget.driverVehicle}\n'
        '💰 Fare: ₹${widget.totalFare}\n\n'
        '📡 Live Location: https://maps.google.com/?q=$lat,$lng\n\n'
        'Track the ride in real-time!';
  }

  Future<void> _shareViaSMS() async {
    final message = Uri.encodeComponent(_buildShareMessage());
    final uri = Uri.parse('sms:?body=$message');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _shareViaEmail() async {
    final subject = Uri.encodeComponent('Torkk Live Trip — ${widget.customerName}');
    final body = Uri.encodeComponent(_buildShareMessage());
    final uri = Uri.parse('mailto:?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _shareViaWhatsApp() async {
    final message = Uri.encodeComponent(_buildShareMessage());
    final uri = Uri.parse('https://wa.me/?text=$message');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareNow() async {
    setState(() => _isSharing = true);
    await _shareViaSMS();
    setState(() => _isSharing = false);
  }

  void _copyLink() {
    final lat = _currentPosition?.latitude.toStringAsFixed(6) ?? '28.6139';
    final lng = _currentPosition?.longitude.toStringAsFixed(6) ?? '77.2090';
    Clipboard.setData(ClipboardData(text: 'https://maps.google.com/?q=$lat,$lng'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Live location link copied!'), duration: Duration(seconds: 2)),
    );
  }

  void _showContactPicker(Color primaryColor) async {
    if (!await FlutterContacts.requestPermission()) return;
    
    final allContacts = await FlutterContacts.getContacts(withProperties: true);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Select Emergency Contact', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: allContacts.length,
                    itemBuilder: (context, index) {
                      final c = allContacts[index];
                      final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
                      if (phone.isEmpty) return const SizedBox();
                      
                      final name = c.displayName;
                      final initials = name.isNotEmpty
                          ? (name.split(' ').length > 1
                              ? '${name[0]}${name.split(' ')[1][0]}'.toUpperCase()
                              : name.substring(0, math.min(2, name.length)).toUpperCase())
                          : 'XX';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: primaryColor.withValues(alpha: 0.15),
                          child: Text(initials, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(phone),
                        onTap: () {
                          setState(() {
                            // Add to our main list if not there
                            final exists = _contacts.indexWhere((existing) => existing['phone'] == phone);
                            if (exists == -1) {
                              _contacts.insert(0, {
                                'name': name,
                                'phone': phone,
                                'initials': initials,
                                'relation': 'Emergency'
                              });
                              _selectedContacts.add(0);
                            } else {
                              _selectedContacts.add(exists);
                            }
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPink = CustomerApp.isPinkTheme.value;
    final primaryColor = isPink ? const Color(0xFFEC4899) : const Color(0xFF3B82F6);
    final secondaryBg = isPink ? const Color(0xFFFDF2F8) : const Color(0xFFEFF6FF);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.close, color: Colors.black87),
        ),
        title: const Text('Share trip status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live Map
            Container(
              height: 180,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: secondaryBg,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _currentPosition != null
                    ? GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                          zoom: 15,
                        ),
                        onMapCreated: (ctrl) => _mapController = ctrl,
                        markers: {
                          Marker(
                            markerId: const MarkerId('user'),
                            position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              isPink ? BitmapDescriptor.hueRose : BitmapDescriptor.hueBlue,
                            ),
                          ),
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on_rounded, color: primaryColor, size: 40),
                            const SizedBox(height: 8),
                            Text('Fetching live location…', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                          ],
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      const Text('Live location', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  GestureDetector(
                    onTap: _copyLink,
                    child: Text('Copy link', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline)),
                  ),
                ],
              ),
            ),
            Text('  Updates automatically while trip is active', style: TextStyle(color: Colors.grey.shade400, fontSize: 11, height: 1)),

            const SizedBox(height: 16),
            // Trip route card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildRouteRow(Icons.circle, widget.pickupName, primaryColor, true, 'Pickup'),
                    Padding(
                      padding: const EdgeInsets.only(left: 6, top: 4, bottom: 4),
                      child: Container(width: 1, height: 20, color: Colors.grey.shade300),
                    ),
                    _buildRouteRow(Icons.square, widget.dropName, Colors.black87, false, 'Drop'),
                  ],
                ),
              ),
            ),

            // Driver card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: secondaryBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text(_driverInitials, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(widget.driverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: isPink ? const Color(0xFFEC4899) : const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(6)),
                                child: Text(widget.driverType, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          Text(widget.driverVehicle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('SEND TO', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
            const SizedBox(height: 12),

            // Contacts list
            _loadingContacts
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _contacts.length,
                    itemBuilder: (context, index) {
                      final contact = _contacts[index];
                      final selected = _selectedContacts.contains(index);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (selected) _selectedContacts.remove(index);
                          else _selectedContacts.add(index);
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: selected ? (isPink ? const Color(0xFFFDF2F8) : const Color(0xFFEFF6FF)) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: selected ? primaryColor : Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                                child: Center(child: Text(contact['initials'] ?? 'XX', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 12))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(contact['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    if (contact['relation'] != null)
                                      Text('${contact['relation']} · ${contact['phone']}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                    if (contact['relation'] == null)
                                      Text(contact['phone'] ?? '', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Checkbox(
                                value: selected,
                                onChanged: (v) => setState(() {
                                  if (v == true) _selectedContacts.add(index);
                                  else _selectedContacts.remove(index);
                                }),
                                activeColor: primaryColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            // Add emergency contact
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () => _showContactPicker(primaryColor),
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline, color: primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Text('Add emergency contact', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('OR SHARE VIA', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
            const SizedBox(height: 16),

            // Share via row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildShareViaButton(Icons.message_rounded, 'Message', primaryColor, _shareViaSMS),
                  _buildShareViaButton(Icons.email_rounded, 'Email', primaryColor, _shareViaEmail),
                  _buildShareViaButton(Icons.apps_rounded, 'More apps', primaryColor, _shareViaWhatsApp),
                ],
              ),
            ),

            const SizedBox(height: 28),
            // Share Trip Now button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: _isSharing ? null : _shareNow,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _isSharing ? Colors.grey.shade300 : primaryColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: _isSharing
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text('SHARE TRIP NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, Color color, bool isPrimary, String tag) {
    return Row(
      children: [
        Icon(icon, color: isPrimary ? color : Colors.black87, size: 10),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tag, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
              Text(label.split(',').first, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShareViaButton(IconData icon, String label, Color primaryColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: primaryColor, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }
}

class CustomerRideHistoryScreen extends StatefulWidget {
  const CustomerRideHistoryScreen({super.key});

  @override
  State<CustomerRideHistoryScreen> createState() => _CustomerRideHistoryScreenState();
}

class _CustomerRideHistoryScreenState extends State<CustomerRideHistoryScreen> {
  List<dynamic> _rides = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';
      if (phone.isEmpty) {
        setState(() { _error = 'User not logged in'; _isLoading = false; });
        return;
      }
      final history = await RideService.getHistory(phone);
      setState(() { _rides = history; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final minute = date.minute.toString().padLeft(2, '0');
      final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
      final ampm = date.hour >= 12 ? 'PM' : 'AM';
      return '${months[date.month-1]} ${date.day}, ${date.year}  $hour:$minute $ampm';
    } catch (e) {
      return isoString;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      case 'ongoing': return Colors.orange;
      default: return Colors.blue;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed': return Icons.check_circle_rounded;
      case 'cancelled': return Icons.cancel_rounded;
      default: return Icons.access_time_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPink = CustomerApp.isPinkTheme.value;
    final primaryColor = isPink ? const Color(0xFFEC4899) : const Color(0xFF3B82F6);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Ride History', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.error_outline_rounded, size: 60, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text('Something went wrong', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _fetchHistory, style: ElevatedButton.styleFrom(backgroundColor: primaryColor), child: const Text('Retry', style: TextStyle(color: Colors.white))),
                ]))
              : _rides.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.history_rounded, size: 72, color: Colors.grey.shade200),
                      const SizedBox(height: 16),
                      Text('No rides yet', style: TextStyle(color: Colors.grey.shade500, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('Your completed rides will appear here', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                    ]))
                  : RefreshIndicator(
                      color: primaryColor,
                      onRefresh: _fetchHistory,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _rides.length,
                        itemBuilder: (context, index) {
                          final ride = _rides[index];
                          final pickup = ride['pickup_address'] ?? 'Unknown';
                          final drop = ride['drop_address'] ?? 'Unknown';
                          final fare = ride['fare'] ?? 0;
                          final date = _formatDate(ride['date'] ?? '');
                          final status = (ride['status'] ?? 'completed') as String;
                          final sc = _statusColor(status);
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                                        child: Icon(Icons.electric_bike_rounded, color: primaryColor, size: 26),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                  Icon(_statusIcon(status), color: sc, size: 12),
                                                  const SizedBox(width: 4),
                                                  Text(status[0].toUpperCase() + status.substring(1), style: TextStyle(color: sc, fontSize: 11, fontWeight: FontWeight.bold)),
                                                ]),
                                              ),
                                              Text('₹${(fare as num).toInt()}', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 20)),
                                            ]),
                                            const SizedBox(height: 6),
                                            Text(date, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
                                  ),
                                  child: Column(
                                    children: [
                                      _buildRouteRow(Icons.fiber_manual_record_rounded, Colors.green, pickup),
                                      const SizedBox(height: 6),
                                      _buildRouteRow(Icons.location_on_rounded, Colors.red, drop),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildRouteRow(IconData icon, Color iconColor, String address) {
    return Row(children: [
      Icon(icon, color: iconColor, size: 14),
      const SizedBox(width: 8),
      Expanded(child: Text(address, style: TextStyle(color: Colors.grey.shade600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
  }
}


// --- CUSTOMER RIDE RECEIPT / RATING SCREEN ---
class CustomerRideReceiptScreen extends StatefulWidget {
  const CustomerRideReceiptScreen({super.key});

  @override
  State<CustomerRideReceiptScreen> createState() => _CustomerRideReceiptScreenState();
}

class _CustomerRideReceiptScreenState extends State<CustomerRideReceiptScreen> {
  int _rating = 4; // default 4 stars
  int _selectedTipIndex = 1; // default ₹20
  final _feedbackController = TextEditingController();
  String _customerName = 'Guest';
  String _dropLocation = 'your destination';
  double _distanceKm = 6.2;
  String _paymentMethod = 'Torkk Wallet';

  final List<int> _tipAmounts = [10, 20, 30];

  String? _driverNameOverride;
  String? _driverVehicleOverride;
  String? _driverTypeOverride;
  double? _totalFareOverride;

  bool _isInit = false;
  bool _isLoadingLatest = false;
  bool _isFromFooter = false;

  // Driver info based on theme or override
  String get _driverName => _driverNameOverride ?? (CustomerApp.isPinkTheme.value ? 'Sneha Reddy' : 'Rahul Sharma');
  String get _driverInitials => _driverName.split(' ').map((e) => e[0]).take(2).join().toUpperCase();
  String get _carDetails => _driverVehicleOverride ?? (CustomerApp.isPinkTheme.value ? 'Tata Nexon EV · KA 03 CD 5678' : 'Tata Nexon EV · DL 01 AB 1234');

  // Fare calculation
  double get _baseFare => 79;
  double get _distanceFare => _distanceKm * 12;
  double get _taxes => 2;
  double get _totalFare => _totalFareOverride ?? (_baseFare + _distanceFare + _taxes);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? '';
    if (name.isNotEmpty && mounted) {
      setState(() => _customerName = name);
    }
  }

  Future<void> _fetchLatestRide() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    if (phone.isEmpty) return;

    if (!mounted) return;
    setState(() => _isLoadingLatest = true);

    try {
      final res = await http.get(Uri.parse('${ApiConstants.baseUrl}/api/ride/history?phone=$phone'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'success') {
          final history = data['history'] as List;
          if (history.isNotEmpty) {
            final latest = history.first;
            if (mounted) {
              setState(() {
                _dropLocation = latest['drop_address'] ?? _dropLocation;
                _totalFareOverride = (latest['fare'] as num?)?.toDouble();
                _distanceKm = 0; // Since distance isn't in history api right now, we can show 0 or dummy
                if (_totalFareOverride != null) {
                   // if we have real fare, let's reverse engineer distance roughly for display
                   _distanceKm = math.max(0, (_totalFareOverride! - _baseFare - _taxes) / 12);
                }
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching latest ride: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLatest = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      _isInit = true;
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _dropLocation = args['dropLocation'] ?? _dropLocation;
        _distanceKm = double.tryParse(args['distance']?.toString() ?? '') ?? _distanceKm;
        _paymentMethod = args['payment'] ?? _paymentMethod;
        _driverNameOverride = args['driverName'];
        _driverVehicleOverride = args['driverVehicle'];
        _driverTypeOverride = args['driverType'];
        if (args['totalFare'] != null) {
          _totalFareOverride = (args['totalFare'] as num).toDouble();
        }
      } else {
        _isFromFooter = true;
        _fetchLatestRide();
      }
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPink = CustomerApp.isPinkTheme.value;
    final primaryColor = isPink ? const Color(0xFFEC4899) : const Color(0xFF3B82F6);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoadingLatest
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Checkmark icon
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: primaryColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 6))],
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 20),
              const Text('Trip completed', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 6),
              Text(
                'You arrived at ${_dropLocation.split(',').first}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 28),
              // Driver card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isPink ? const Color(0xFFFDF2F8) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: Text(_driverInitials, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 16))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(_driverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                                ),
                                child: Text(_driverTypeOverride ?? (isPink ? 'Female driver' : 'Male driver'),
                                    style: TextStyle(color: primaryColor, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          Text(_carDetails, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              // Payment method badge + fare breakdown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                      ),
                      child: Text('Paid via $_paymentMethod', style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    _buildWalletFareRow('Base fare', '₹${_baseFare.round()}'),
                    const SizedBox(height: 8),
                    _buildWalletFareRow('Distance (${_distanceKm.toStringAsFixed(1)} km)', '₹${_distanceFare.round()}'),
                    const SizedBox(height: 8),
                    _buildWalletFareRow('Taxes and fees', '₹${_taxes.round()}'),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total paid', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF0F172A))),
                        Text('₹${_totalFare.round()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF0F172A))),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),
              // Rate your ride
              Text('Rate your ride with ${_driverName.split(' ').first}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return GestureDetector(
                    onTap: () => setState(() => _rating = index + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        index < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                        color: index < _rating ? const Color(0xFFFBBF24) : Colors.grey.shade300,
                        size: 40,
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 20),
              // Feedback text field
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  controller: _feedbackController,
                  decoration: InputDecoration(
                    hintText: 'Add feedback (optional)',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    border: InputBorder.none,
                  ),
                  maxLines: 2,
                ),
              ),

              const SizedBox(height: 28),
              // Add a Tip section
              Align(
                alignment: Alignment.centerLeft,
                child: Text('ADD A TIP', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (int i = 0; i < _tipAmounts.length; i++) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTipIndex = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _selectedTipIndex == i ? primaryColor : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _selectedTipIndex == i ? primaryColor : Colors.grey.shade300),
                          ),
                          child: Center(
                            child: Text(
                              '₹${_tipAmounts[i]}',
                              style: TextStyle(
                                color: _selectedTipIndex == i ? Colors.white : const Color(0xFF0F172A),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (i < _tipAmounts.length) const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTipIndex = 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _selectedTipIndex == 3 ? primaryColor : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _selectedTipIndex == 3 ? primaryColor : Colors.grey.shade300),
                        ),
                        child: Center(
                          child: Text(
                            'Other',
                            style: TextStyle(
                              color: _selectedTipIndex == 3 ? Colors.white : const Color(0xFF0F172A),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),
              // Done button
              GestureDetector(
                onTap: () {
                  Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: primaryColor.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: const Center(
                    child: Text('DONE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // View Wallet button
              if (_isFromFooter)
                GestureDetector(
                  onTap: () {
                    Navigator.pushNamed(context, '/wallet');
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: primaryColor, width: 2),
                    ),
                    child: Center(
                      child: Text('VIEW MY WALLET', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWalletFareRow(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        Text(value, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
      ],
    );
  }
}

// --- CUSTOMER WALLET SCREEN (Real Wallet with Balance & Add Money) ---
class CustomerWalletScreen extends StatefulWidget {
  const CustomerWalletScreen({super.key});

  @override
  State<CustomerWalletScreen> createState() => _CustomerWalletScreenState();
}

class _CustomerWalletScreenState extends State<CustomerWalletScreen> {
  double _balance = 0.0;
  bool _isLoading = true;
  bool _isAddingMoney = false;
  String _userPhone = '';
  String _userName = 'User';
  List<Map<String, dynamic>> _transactions = [];
  late Razorpay _razorpay;
  double _pendingAmount = 0;
  int _selectedQuickAmount = -1;
  final TextEditingController _customAmountController = TextEditingController();

  final List<int> _quickAmounts = [100, 200, 500, 1000];

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleWalletPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleWalletPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _loadData();
  }

  @override
  void dispose() {
    _razorpay.clear();
    _customAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final name = prefs.getString('user_name') ?? 'User';
    if (!mounted) return;
    setState(() {
      _userPhone = phone;
      _userName = name;
    });
    if (phone.isNotEmpty) {
      await Future.wait([_fetchBalance(phone), _fetchTransactions(phone)]);
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchBalance(String phone) async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/wallet/balance?phone=$phone'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted && data['status'] == 'success') {
          setState(() {
            _balance = (data['balance'] as num?)?.toDouble() ?? 0.0;
          });
        }
      }
    } catch (e) {
      debugPrint('Wallet balance error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTransactions(String phone) async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/wallet/transactions?phone=$phone'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted && data['status'] == 'success') {
          final txList = (data['transactions'] as List?);
          setState(() {
            _transactions = txList?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint('Wallet transactions error: $e');
    }
  }

  Future<void> _initiateAddMoney(double amount) async {
    if (_userPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to add money'), backgroundColor: Colors.red),
      );
      return;
    }
    if (amount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum amount is ₹10'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isAddingMoney = true);
    _pendingAmount = amount;

    try {
      final res = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/wallet/add-money'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'phone': _userPhone, 'amount': amount}),
      );
      final data = json.decode(res.body);
      if (data['status'] == 'success') {
        // Open Razorpay
        final amountPaise = data['amount_paise'] as int;
        final options = {
          'key': 'rzp_live_TAvPrH4AtVDEqF',
          'amount': amountPaise,
          'name': 'Torkk Wallet',
          'description': 'Add Money to Torkk Wallet',
          'prefill': {
            'contact': _userPhone,
            'email': 'user@torkk.com',
          },
          'theme': {'color': CustomerApp.isPinkTheme.value ? '#EC4899' : '#3B82F6'},
        };
        _razorpay.open(options);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Failed to initiate payment'), backgroundColor: Colors.red),
          );
        }
        setState(() => _isAddingMoney = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isAddingMoney = false);
    }
  }

  void _handleWalletPaymentSuccess(PaymentSuccessResponse response) async {
    final paymentId = response.paymentId ?? 'pay_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final res = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/wallet/verify-payment'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone': _userPhone,
          'amount': _pendingAmount,
          'razorpay_payment_id': paymentId,
          'description': 'Added ₹${_pendingAmount.toStringAsFixed(0)} via Razorpay',
        }),
      );
      final data = json.decode(res.body);
      if (mounted) {
        if (data['status'] == 'success') {
          setState(() {
            _balance = (data['new_balance'] as num?)?.toDouble() ?? _balance;
            _isAddingMoney = false;
            _selectedQuickAmount = -1;
            _customAmountController.clear();
          });
          // Refresh transactions
          _fetchTransactions(_userPhone);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('₹${_pendingAmount.toStringAsFixed(0)} added to wallet! 🎉'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Payment verification failed'), backgroundColor: Colors.red),
          );
          setState(() => _isAddingMoney = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment recorded, balance will update shortly'), backgroundColor: Colors.orange),
        );
        setState(() => _isAddingMoney = false);
      }
    }
  }

  void _handleWalletPaymentError(PaymentFailureResponse response) {
    if (mounted) {
      setState(() => _isAddingMoney = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed: ${response.message ?? 'Unknown error'}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('External wallet: ${response.walletName}');
  }

  void _showAddMoneySheet() {
    final isPink = CustomerApp.isPinkTheme.value;
    final primaryColor = isPink ? const Color(0xFFEC4899) : const Color(0xFF3B82F6);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Add Money to Wallet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
              const SizedBox(height: 6),
              Text('Current balance: ₹${_balance.toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
              const SizedBox(height: 24),
              Text('QUICK ADD', style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _quickAmounts.map((amt) {
                  final isSelected = _selectedQuickAmount == amt;
                  return GestureDetector(
                    onTap: () {
                      setModalState(() => _selectedQuickAmount = amt);
                      _customAmountController.text = amt.toString();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? primaryColor : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? primaryColor : Colors.grey.shade200,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Text('₹$amt',
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF0F172A),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          )),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text('OR ENTER AMOUNT', style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Text('₹', style: TextStyle(fontSize: 20, color: primaryColor, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _customAmountController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(color: Colors.grey.shade300),
                          border: InputBorder.none,
                        ),
                        onChanged: (v) => setModalState(() => _selectedQuickAmount = -1),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _isAddingMoney
                    ? null
                    : () {
                        final text = _customAmountController.text.trim();
                        final amount = double.tryParse(text) ?? 0;
                        if (amount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a valid amount'), backgroundColor: Colors.orange),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        _initiateAddMoney(amount);
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    color: _isAddingMoney ? primaryColor.withValues(alpha: 0.6) : primaryColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: primaryColor.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))
                    ],
                  ),
                  child: Center(
                    child: _isAddingMoney
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text('PROCEED TO PAY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${months[dt.month - 1]} · $hour:$min $ampm';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPink = CustomerApp.isPinkTheme.value;
    final primaryColor = isPink ? const Color(0xFFEC4899) : const Color(0xFF3B82F6);
    final gradientColors = isPink
        ? [const Color(0xFFEC4899), const Color(0xFFBE185D)]
        : [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Wallet', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: primaryColor,
        onRefresh: _loadData,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  // Balance Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: primaryColor.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 10))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_userName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                const SizedBox(height: 2),
                                const Text('Torkk Wallet', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 26),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text('Total Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          '₹${_balance.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: -1),
                        ),
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: _showAddMoneySheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded, color: primaryColor, size: 20),
                                const SizedBox(width: 6),
                                Text('Add Money', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Transaction History
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Transaction History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      if (_transactions.isNotEmpty)
                        Text('${_transactions.length} entries', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_transactions.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('No transactions yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text('Add money to get started!', style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                        ],
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _transactions.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100, indent: 60),
                        itemBuilder: (context, index) {
                          final tx = _transactions[index];
                          final isCredit = tx['type'] == 'credit';
                          final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
                          final desc = tx['description'] ?? (isCredit ? 'Money added' : 'Payment');
                          final date = _formatDate(tx['created_at']);

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: isCredit
                                        ? Colors.green.shade50
                                        : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                    color: isCredit ? Colors.green : Colors.red,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(desc,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF0F172A)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 3),
                                      Text(date, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${isCredit ? '+' : '-'}₹${amount.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    color: isCredit ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddMoneySheet,
              backgroundColor: primaryColor,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Add Money', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
    );
  }
}

class CustomerSupportScreen extends StatelessWidget {
  const CustomerSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text('Need assistance with a recent ride?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.chat_bubble_rounded),
              title: const Text('Live Support Chat'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.email_rounded),
              title: const Text('Email Support'),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  String _userName = 'Guest User';
  String _userPhone = '';
  String _userGender = 'Female';
  bool _isFaceVerified = true;
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? 'Guest User';
        _userPhone = prefs.getString('user_phone') ?? '+91 9876543210';
        _userGender = CustomerApp.isPinkTheme.value ? 'Female' : 'Male';
        _isFaceVerified = true;
        _profileImagePath = prefs.getString('profile_image_path');
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_image_path', pickedFile.path);
      if (mounted) setState(() => _profileImagePath = pickedFile.path);
    }
  }

  Widget _buildProfileOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Widget? trailing,
    Color iconColor = Colors.black87,
    bool isDestructive = false,
  }) {
    final primaryColor = CustomerApp.isPinkTheme.value ? const Color(0xFFEC4899) : const Color(0xFF3B82F6);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDestructive ? Colors.red.shade50 : primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: isDestructive ? Colors.red : primaryColor, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDestructive ? Colors.red : const Color(0xFF0F172A),
        ),
      ),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)) : null,
      trailing: trailing ?? (isDestructive ? null : const Icon(Icons.chevron_right_rounded, color: Colors.black26)),
      onTap: onTap,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPink = CustomerApp.isPinkTheme.value;
    final primaryColor = isPink ? const Color(0xFFEC4899) : const Color(0xFF3B82F6);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Profile', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Stack(
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 2),
                            image: _profileImagePath != null
                                ? DecorationImage(image: FileImage(File(_profileImagePath!)), fit: BoxFit.cover)
                                : null,
                          ),
                          child: _profileImagePath == null
                              ? Icon(Icons.person_rounded, size: 40, color: primaryColor)
                              : null,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_userName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        const SizedBox(height: 4),
                        Text(_userPhone, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(_userGender, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 8),
                            if (_isFaceVerified)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.verified_rounded, color: Colors.green.shade600, size: 14),
                                    const SizedBox(width: 4),
                                    Text('Verified', style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),

            // Main Settings
            Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Account & Rides'),
                  _buildProfileOption(
                    icon: Icons.location_on_outlined,
                    title: 'Saved Addresses',
                    onTap: () => Navigator.pushNamed(context, '/profile/saved-addresses'),
                  ),
                  _buildProfileOption(
                    icon: Icons.favorite_border_rounded,
                    title: 'Favourite Places',
                    onTap: () => Navigator.pushNamed(context, '/profile/favourite-places'),
                  ),
                  _buildProfileOption(
                    icon: Icons.contact_emergency_outlined,
                    title: 'Emergency Contacts',
                    onTap: () => Navigator.pushNamed(context, '/profile/emergency-contacts'),
                  ),
                  _buildProfileOption(
                    icon: Icons.history_rounded,
                    title: 'Ride History',
                    onTap: () => Navigator.pushNamed(context, '/history'),
                  ),
                  
                  _buildSectionHeader('Payments & Rewards'),
                  _buildProfileOption(
                    icon: Icons.card_membership_rounded,
                    title: 'Subscription',
                    subtitle: 'Manage active plans',
                    onTap: () => Navigator.pushNamed(context, '/profile/subscription'),
                  ),
                  _buildProfileOption(
                    icon: Icons.card_giftcard_rounded,
                    title: 'Referral & Rewards',
                    onTap: () => Navigator.pushNamed(context, '/profile/referral'),
                  ),

                  _buildSectionHeader('App Settings'),
                  _buildProfileOption(
                    icon: Icons.notifications_none_rounded,
                    title: 'Notification Settings',
                    onTap: () => Navigator.pushNamed(context, '/profile/notification-settings'),
                  ),
                  _buildProfileOption(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Settings',
                    onTap: () => Navigator.pushNamed(context, '/profile/privacy-settings'),
                  ),
                  _buildProfileOption(
                    icon: Icons.language_rounded,
                    title: 'Language',
                    subtitle: 'English',
                    onTap: () => Navigator.pushNamed(context, '/profile/language'),
                  ),

                  _buildSectionHeader('More'),
                  _buildProfileOption(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & Support',
                    onTap: () => Navigator.pushNamed(context, '/profile/help-support'),
                  ),
                  _buildProfileOption(
                    icon: Icons.info_outline_rounded,
                    title: 'About Torkk',
                    onTap: () => Navigator.pushNamed(context, '/profile/about'),
                  ),
                  _buildProfileOption(
                    icon: Icons.description_outlined,
                    title: 'Terms & Conditions',
                    onTap: () => Navigator.pushNamed(context, '/profile/terms'),
                  ),
                  _buildProfileOption(
                    icon: Icons.shield_outlined,
                    title: 'Privacy Policy',
                    onTap: () => Navigator.pushNamed(context, '/profile/privacy-policy'),
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  _buildProfileOption(
                    icon: Icons.logout_rounded,
                    title: 'Logout',
                    isDestructive: true,
                    onTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final recentLocations = prefs.getString('recent_locations');
                      await prefs.clear();
                      if (recentLocations != null) {
                        await prefs.setString('recent_locations', recentLocations);
                      }
                      if (context.mounted) {
                        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                      }
                    },
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerNotificationsScreen extends StatelessWidget {
  const CustomerNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Card(
            child: ListTile(
              leading: Icon(Icons.local_offer_rounded, color: Colors.green),
              title: Text('Discount Coupon Added'),
              subtitle: Text('Get 20% off on your next premium status ride!'),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
//   PREMIUM UI/UX HELPER WIDGETS & PAINTERS
// ==========================================

class BouncingWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const BouncingWidget({super.key, required this.child, this.onTap});

  @override
  State<BouncingWidget> createState() => _BouncingWidgetState();
}

class _BouncingWidgetState extends State<BouncingWidget> with SingleTickerProviderStateMixin {
  late double _scale;
  late AnimationController _controller;

  @override
  void initState() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 0.05,
    )..addListener(() {
        setState(() {});
      });
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scale = 1 - _controller.value;
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap != null) _controller.forward();
      },
      onTapUp: (_) {
        if (widget.onTap != null) {
          _controller.reverse();
          widget.onTap!();
        }
      },
      onTapCancel: () {
        if (widget.onTap != null) _controller.reverse();
      },
      child: Transform.scale(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}

class AadhaarScannerPainter extends CustomPainter {
  final double animationValue;

  AadhaarScannerPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paintCorner = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    final double length = 24.0;

    canvas.drawLine(const Offset(4, 4), Offset(4, 4 + length), paintCorner);
    canvas.drawLine(const Offset(4, 4), Offset(4 + length, 4), paintCorner);

    canvas.drawLine(Offset(size.width - 4, 4), Offset(size.width - 4, 4 + length), paintCorner);
    canvas.drawLine(Offset(size.width - 4, 4), Offset(size.width - 4 - length, 4), paintCorner);

    canvas.drawLine(Offset(4, size.height - 4), Offset(4, size.height - 4 - length), paintCorner);
    canvas.drawLine(Offset(4, size.height - 4), Offset(4 + length, size.height - 4), paintCorner);

    canvas.drawLine(Offset(size.width - 4, size.height - 4), Offset(size.width - 4, size.height - 4 - length), paintCorner);
    canvas.drawLine(Offset(size.width - 4, size.height - 4), Offset(size.width - 4 - length, size.height - 4), paintCorner);

    final double y = size.height * animationValue;
    final paintBeam = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF10B981).withValues(alpha: 0.0),
          const Color(0xFF10B981).withValues(alpha: 0.6),
          const Color(0xFF10B981).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 10, size.width, 20));

    canvas.drawRect(Rect.fromLTWH(0, y - 10, size.width, 20), paintBeam);

    final paintLaser = Paint()
      ..color = const Color(0xFF34D399)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paintLaser);
  }

  @override
  bool shouldRepaint(covariant AadhaarScannerPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

class ShimmerLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerLoader> createState() => _ShimmerLoaderState();
}

class _ShimmerLoaderState extends State<ShimmerLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Color(0xFFE2E8F0),
                Color(0xFFF1F5F9),
                Color(0xFFE2E8F0),
              ],
              stops: [
                0.0,
                0.3 + 0.4 * _controller.value,
                1.0,
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================
// CUSTOMER SCHEDULE SCREEN
// ============================================
class CustomerScheduleScreen extends StatefulWidget {
  const CustomerScheduleScreen({super.key});

  @override
  State<CustomerScheduleScreen> createState() => _CustomerScheduleScreenState();
}

class _CustomerScheduleScreenState extends State<CustomerScheduleScreen> {
  int _selectedDateIndex = 0;
  bool _isAm = true;
  int? _selectedHour;
  int? _selectedMinute;

  List<Map<String, String>> _getDates() {
    final now = DateTime.now();
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return List.generate(3, (i) {
      final d = now.add(Duration(days: i));
      final label = i == 0 ? 'Today' : i == 1 ? 'Tomorrow' : days[d.weekday - 1];
      final sub = '${months[d.month - 1]} ${d.day}';
      return {'label': label, 'sub': sub};
    });
  }

  String get _timeDisplay {
    if (_selectedHour == null) return 'HH : MM';
    final h = _selectedHour.toString().padLeft(2, '0');
    final m = (_selectedMinute ?? 0).toString().padLeft(2, '0');
    return '$h : $m';
  }

  void _showTimePicker(Color primaryColor) {
    int? tempHour = _selectedHour;
    int? tempMin = _selectedMinute;
    bool tempAm = _isAm;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.65,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Select Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A))),
                      Container(
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          children: ['AM', 'PM'].map((period) {
                            final active = (period == 'AM') == tempAm;
                            return GestureDetector(
                              onTap: () => setSheet(() => tempAm = period == 'AM'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                decoration: BoxDecoration(
                                  color: active ? primaryColor : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(period, style: TextStyle(color: active ? Colors.white : Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('Hour', style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView(
                                children: List.generate(12, (i) {
                                  final h = i + 1;
                                  final sel = tempHour == h;
                                  return GestureDetector(
                                    onTap: () => setSheet(() => tempHour = h),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: sel ? primaryColor : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(child: Text(h.toString().padLeft(2, '0'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: sel ? Colors.white : const Color(0xFF0F172A)))),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, color: Colors.grey.shade100),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('Minute', style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView(
                                children: [0, 15, 30, 45].map((m) {
                                  final sel = tempMin == m;
                                  return GestureDetector(
                                    onTap: () => setSheet(() => tempMin = m),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: sel ? primaryColor : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(child: Text(m.toString().padLeft(2, '0'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: sel ? Colors.white : const Color(0xFF0F172A)))),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: GestureDetector(
                    onTap: () {
                      if (tempHour != null) {
                        setState(() {
                          _selectedHour = tempHour;
                          _selectedMinute = tempMin ?? 0;
                          _isAm = tempAm;
                        });
                        Navigator.pop(ctx);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an hour first')));
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(14)),
                      child: const Center(child: Text('Confirm Time', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPink = CustomerApp.isPinkTheme.value;
    final primaryColor = isPink ? const Color(0xFFEC4899) : const Color(0xFF3B82F6);
    final dates = _getDates();
    final timeSet = _selectedHour != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.chevron_left, color: Color(0xFF0F172A)),
          ),
        ),
        title: const Text('Schedule ride', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('When do you need a cab?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
            const SizedBox(height: 6),
            Text('You can book up to 2 days ahead of time', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
            const SizedBox(height: 32),
            Text('DATE', style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            Row(
              children: List.generate(3, (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 12 : 0),
                  child: _buildDateCard(i, dates[i]['label']!, dates[i]['sub']!, primaryColor),
                ),
              )),
            ),
            const SizedBox(height: 32),
            Text('TIME', style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _showTimePicker(primaryColor),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: timeSet ? primaryColor : Colors.grey.shade200, width: timeSet ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: Icon(Icons.access_time_rounded, color: primaryColor, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _timeDisplay,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: timeSet ? const Color(0xFF0F172A) : Colors.grey.shade400, letterSpacing: 2),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _isAm = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: _isAm ? primaryColor : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                              child: Text('AM', style: TextStyle(color: _isAm ? Colors.white : Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _isAm = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: !_isAm ? primaryColor : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                              child: Text('PM', style: TextStyle(color: !_isAm ? Colors.white : Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (timeSet) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: primaryColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      'Ride for ${dates[_selectedDateIndex]['label']} at $_timeDisplay ${_isAm ? 'AM' : 'PM'}',
                      style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600, fontSize: 12),
                    )),
                  ],
                ),
              ),
            ],
            const Spacer(),
            GestureDetector(
              onTap: () async {
                if (!timeSet) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a time first')));
                  return;
                }
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomerSearchScreen(
                      scheduledDate: dates[_selectedDateIndex]['label'],
                      scheduledTime: '$_timeDisplay ${_isAm ? 'AM' : 'PM'}',
                    ),
                  ),
                );
                if (result != null && context.mounted) {
                  // Forward the picked pickup/drop (+ schedule) map up to whoever
                  // pushed this schedule screen, so it can enter the real ride flow.
                  Navigator.pop(context, result);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: timeSet ? primaryColor : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: timeSet ? [BoxShadow(color: primaryColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] : null,
                ),
                child: const Center(child: Text('Proceed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDateCard(int index, String title, String subtitle, Color primaryColor) {
    final isSelected = _selectedDateIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedDateIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? primaryColor : Colors.grey.shade200, width: isSelected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Icon(Icons.calendar_today_rounded, color: isSelected ? primaryColor : Colors.grey.shade400, size: 20),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ============================================
// CUSTOMER PASSENGER DETAILS SCREEN
// ============================================
class CustomerPassengerDetailsScreen extends StatefulWidget {
  final String rideType;
  const CustomerPassengerDetailsScreen({super.key, required this.rideType});

  @override
  State<CustomerPassengerDetailsScreen> createState() => _CustomerPassengerDetailsScreenState();
}

class _CustomerPassengerDetailsScreenState extends State<CustomerPassengerDetailsScreen> {
  int _maleCount = 0;
  int _femaleCount = 0;

  int get _maxSeats {
    if (widget.rideType.toLowerCase().contains('auto')) return 3;
    if (widget.rideType.toLowerCase().contains('ev')) return 4;
    if (widget.rideType.toLowerCase().contains('7')) return 7;
    return 1; // Bike
  }

  int get _price {
    return 34; // Dummy price
  }
  
  IconData get _rideIcon {
    if (widget.rideType.toLowerCase().contains('auto')) return Icons.electric_rickshaw_rounded;
    if (widget.rideType.toLowerCase().contains('7')) return Icons.directions_car_filled_rounded;
    if (widget.rideType.toLowerCase().contains('bike')) return Icons.pedal_bike_rounded;
    return Icons.local_taxi_rounded; // EV
  }

  @override
  Widget build(BuildContext context) {
    final totalSelected = _maleCount + _femaleCount;
    final canAdd = totalSelected < _maxSeats;
    final canProceed = totalSelected > 0;
    
    final primaryColor = const Color(0xFF3B82F6); // Assuming base blue for this screen
    final textColor = const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.chevron_left, color: Color(0xFF0F172A)),
          ),
        ),
        title: const Text('Passenger details', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SELECTED RIDE', style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(_rideIcon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.rideType, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 2),
                              Text('2 min away · Seats up to $_maxSeats', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text('₹$_price', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  Text('WHO\'S RIDING', style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        _buildPassengerRow('Male passengers', true, _maleCount, () {
                          if (_maleCount > 0) setState(() => _maleCount--);
                        }, () {
                          if (canAdd) setState(() => _maleCount++);
                        }),
                        Divider(height: 1, color: Colors.grey.shade200),
                        _buildPassengerRow('Female passengers', false, _femaleCount, () {
                          if (_femaleCount > 0) setState(() => _femaleCount--);
                        }, () {
                          if (canAdd) setState(() => _femaleCount++);
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$totalSelected of $_maxSeats seats selected', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 11)),
                      Text('Choose at least 1 passenger', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  Text('DRIVER MATCH', style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: totalSelected == 0 ? const Color(0xFF0F172A) : const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(totalSelected == 0 ? Icons.star_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(totalSelected == 0 ? 'AWAITING SELECTION' : 'DRIVER MATCHED', style: TextStyle(color: totalSelected == 0 ? Colors.grey.shade500 : const Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              const SizedBox(height: 4),
                              Text(totalSelected == 0 ? 'No driver assigned yet' : (_maleCount >= _femaleCount ? 'Rahul Sharma (Male)' : 'Sneha Reddy (Female)'), style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(totalSelected == 0 ? 'Add passengers above to see your matched driver.' : '4.8 ★ · 2 min away', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Driver gender is auto-assigned based on the majority of passengers in the group, for everyone\'s comfort and safety. If it\'s a tie, any available driver is matched.',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 10, height: 1.5),
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(24),
            child: GestureDetector(
              onTap: canProceed ? () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Finding driver...')));
              } : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: canProceed ? primaryColor : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: canProceed ? [BoxShadow(color: primaryColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] : null,
                ),
                child: const Center(
                  child: Text('CONFIRM & FIND DRIVER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerRow(String title, bool isMale, int count, VoidCallback onRemove, VoidCallback onAdd) {
    final iconBgColor = isMale ? const Color(0xFFEFF6FF) : const Color(0xFFFDF2F8);
    final iconColor = isMale ? const Color(0xFF3B82F6) : const Color(0xFFEC4899);
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_outline, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text('Traveling in this trip', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
              ],
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.remove, color: count > 0 ? const Color(0xFF0F172A) : Colors.grey.shade300, size: 16),
                ),
              ),
              const SizedBox(width: 16),
              Text('$count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: onAdd,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.add, color: Color(0xFF0F172A), size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
