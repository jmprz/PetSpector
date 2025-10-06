import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

Future<void> syncUserWithSupabase(String uid, String email, String? name) async {
  final existing = await supabase
      .from('users')
      .select()
      .eq('firebase_uid', uid)
      .maybeSingle();

  if (existing == null) {
    await supabase.from('users').insert({
      'firebase_uid': uid,
      'email': email,
      'full_name': name,
    });
  }
}
