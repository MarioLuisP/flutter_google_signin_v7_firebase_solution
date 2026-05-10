import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/auth_provider.dart';

// RULE #1: Firebase.initializeApp() ALWAYS in main(), before runApp().
// If you move it later (e.g. to initState), AuthProvider's constructor
// runs before Firebase is ready → authStateChanges never fires on cold start.
// This was verified by a real 30-minute rollback in production.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // RULE #2: AuthProvider is created here — before the first frame.
      // Its constructor calls _initializeAuthListener(), which wires up
      // authStateChanges.listen(...). The first event on that stream is
      // the user Firebase restored from Keychain/EncryptedSharedPreferences,
      // emitted before the UI builds. No Google Sign-In call needed.
      create: (_) => AuthProvider(),
      child: MaterialApp(
        title: 'Google Sign-In v7 Demo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const _AppGate(),
      ),
    );
  }
}

class _AppGate extends StatefulWidget {
  const _AppGate();

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  @override
  void initState() {
    super.initState();
    // RULE #3: initializeAuth() runs in addPostFrameCallback — needs context.
    // It checks if Firebase already has a user (it usually does after first login).
    // If not, creates an anonymous session so the app always has a user.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().initializeAuth();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return auth.isLoggedIn ? const _HomeScreen() : const _LoginScreen();
      },
    );
  }
}

// ── Home Screen ─────────────────────────────────────────────────────────────
// Shown when Firebase Auth has a real (non-anonymous) user.
// This screen can appear on cold start WITHOUT any Google Sign-In call,
// because Firebase Auth restored the session from local storage.

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Sign-In v7 Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: auth.isLoading ? null : () => auth.signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info card
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: auth.getAvatarColor(),
                      backgroundImage: auth.userPhotoUrl.isNotEmpty
                          ? NetworkImage(auth.userPhotoUrl)
                          : null,
                      child: auth.userPhotoUrl.isEmpty
                          ? Text(
                              auth.userInitials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.userName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (auth.userEmail.isNotEmpty)
                            Text(
                              auth.userEmail,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Persistence proof card — the key demo section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_user, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Persistence Proof',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _MetadataRow(
                      label: 'Account created',
                      value: _formatDate(user?.metadata.creationTime),
                    ),
                    const SizedBox(height: 8),
                    _MetadataRow(
                      label: 'Last Google handshake',
                      value: _formatDate(user?.metadata.lastSignInTime),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: const Text(
                        'Kill this app and reopen it. You will land here again '
                        'without seeing any Google dialog.\n\n'
                        'Firebase Auth read your session from local storage '
                        '(Keychain on iOS, EncryptedSharedPreferences on Android). '
                        'The Google Sign-In SDK was not called.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Architecture explanation card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The Architecture',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const _ArchitectureRow(
                      icon: Icons.vpn_key,
                      color: Colors.orange,
                      label: 'Google Sign-In v7',
                      description:
                          'The key — used ONCE for the initial handshake',
                    ),
                    const SizedBox(height: 8),
                    const _ArchitectureRow(
                      icon: Icons.home,
                      color: Colors.green,
                      label: 'Firebase Auth',
                      description:
                          'The house — persists the session across all restarts',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: auth.isLoading
                    ? null
                    : () => _showDeleteAccountDialog(context, auth),
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: Text(
                  auth.isLoading ? 'Processing...' : 'Delete account',
                  style: const TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return '${date.day}/${date.month}/${date.year} '
        'at ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  void _showDeleteAccountDialog(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          'This action cannot be undone. Your account will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await auth.deleteAccount();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ── Login Screen ─────────────────────────────────────────────────────────────

class _LoginScreen extends StatelessWidget {
  const _LoginScreen();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_open, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              Text(
                'Google Sign-In v7\nPersistence Demo',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in once. Firebase Auth keeps the session.\n'
                'Restart the app — you will still be here.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 48),

              ElevatedButton.icon(
                onPressed:
                    auth.isLoading ? null : () => auth.signInWithGoogle(),
                icon: const Icon(Icons.login),
                label: Text(
                  auth.isLoading ? 'Signing in...' : 'Sign in with Google',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),

              // Apple Sign-In — iOS only. Platform.isIOS (not Theme.of(context).platform)
              if (Platform.isIOS) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed:
                      auth.isLoading ? null : () => auth.signInWithApple(),
                  icon: const Icon(Icons.apple),
                  label: Text(
                    auth.isLoading ? 'Signing in...' : 'Sign in with Apple',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],

              if (auth.lastError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    auth.lastError!,
                    style:
                        TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
              ],

              const SizedBox(height: 32),
              const _HowItWorksSection(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Supporting widgets ───────────────────────────────────────────────────────

class _MetadataRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetadataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 170,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style:
                const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _ArchitectureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String description;
  const _ArchitectureRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              Text(description,
                  style:
                      TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '1. Tap "Sign in with Google" → one Google dialog\n'
            '2. Firebase Auth receives the token and saves the session\n'
            '3. Kill the app, reopen it\n'
            '4. Firebase Auth restores the session from local storage\n'
            '5. No Google dialog. No network call. ~100ms.',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }
}
