import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/posten_login_screen.dart';
import 'theme.dart';

// TODO(Michael): Diese Werte stammen aus dem bestehenden Rezept-App-Projekt.
// Der "Publishable Key" (Anon-Key) ist bewusst öffentlich in einer Client-App
// verwendbar (er wird durch Row Level Security in Supabase abgesichert).
// NIEMALS den service_role-Key hier eintragen!
const supabaseUrl = 'https://rlphbyqulbwrysxctcss.supabase.co';
const supabaseAnonKey = 'sb_publishable_wo5jWkmQKb8BLYXjOPTVCA_bp87Laq3';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const BackfuchsApp());
}

class BackfuchsApp extends StatelessWidget {
  const BackfuchsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Wester's Backfuchs – Produktion",
      debugShowCheckedModeBanner: false,
      theme: buildBackfuchsTheme(),
      home: const PostenLoginScreen(),
    );
  }
}
