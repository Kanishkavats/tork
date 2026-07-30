import re

file_path = 'lib/screens/profile_form_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the saveProfile method
old_method = '''  Future<void> saveProfile() async {
    setState(() => loading = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;

    final usersRef = FirebaseFirestore.instance.collection("users").doc(uid);
    final ridersRef = FirebaseFirestore.instance.collection("riders").doc(uid);

    // 🔹 STEP 1: Save rider profile
    await ridersRef.set({
      "name": nameController.text.trim(),
      "gender": gender,
      "emergencyContact": emergencyController.text.trim(),
      "createdAt": Timestamp.now(),
    });

    // 🔹 STEP 2: Ensure rider role exists in users
    await usersRef.set({
      "roles": {"rider": true},
    }, SetOptions(merge: true)); // merge so we don't overwrite other roles

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {'''

new_method = '''  Future<void> saveProfile() async {
    if (!mounted) return;
    setState(() => loading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final usersRef = FirebaseFirestore.instance.collection("users").doc(uid);
      final ridersRef =
          FirebaseFirestore.instance.collection("riders").doc(uid);

      // 🔹 STEP 1: Save rider profile
      await ridersRef.set({
        "name": nameController.text.trim(),
        "gender": gender,
        "emergencyContact": emergencyController.text.trim(),
        "createdAt": Timestamp.now(),
      });

      // 🔹 STEP 2: Ensure rider role exists in users
      await usersRef.set({
        "roles": {"rider": true},
      }, SetOptions(merge: true)); // merge so we don't overwrite other roles

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving profile: ${e.toString()}")),
      );
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  @override
  void dispose() {
    nameController.dispose();
    emergencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {'''

if old_method in content:
    content = content.replace(old_method, new_method)
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('ProfileFormScreen fixed successfully')
else:
    print('Method not found in file')
