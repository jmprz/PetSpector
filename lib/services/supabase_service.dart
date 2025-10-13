import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';

// Initialize the Supabase client instance
final supabase = Supabase.instance.client;

/// Synchronizes a Firebase user with the 'users' table in Supabase.
/// It checks if a user with the matching 'firebase_uid' already exists
/// before attempting to insert a new record.
Future<void> syncUserWithSupabase(String uid, String email, String? name) async {
  log('Attempting to sync user $uid (Email: $email) with Supabase...');
  
  try {
    // 1. Check if the user already exists in the 'users' table
    final existing = await supabase
        .from('users')
        .select()
        .eq('firebase_uid', uid)
        .maybeSingle(); // Use maybeSingle to get null if no row is found

    if (existing == null) {
      // 2. If the user does not exist, insert a new record
      await supabase.from('users').insert({
        'firebase_uid': uid,
        'email': email,
        // Supabase column names often use snake_case
        'full_name': name,
        'created_at': DateTime.now().toIso8601String(), // Add creation timestamp
      });
      log('Supabase sync successful: New user record created.');
    } else {
      // 3. Optional: Log if user already exists
      log('Supabase sync successful: User record already exists.');
    }
  } catch (e) {
    // Log any errors encountered during the Supabase operation
    log('Supabase sync FAILED for user $uid. Error: $e');
    // We swallow the error here so the Firebase signup can still proceed
    // but log the failure for debugging.
  }
}
