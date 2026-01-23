import 'package:flutter/material.dart';
import 'dart:async';
import 'screens/signup_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
// Retaining the prefix 'fb_auth' to prevent the conflict with Supabase's 'User' class
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'screens/home_screen.dart';
import 'package:camera/camera.dart';
import 'screens/cam_scan_screen.dart'; // NEW: Import the camera screen
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:async/async.dart';
import 'package:async/async.dart' show StreamGroup;
import 'package:rxdart/rxdart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Global variable to store the list of available cameras
List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  try {
    await dotenv.load(fileName: "assets/env");
  } catch (e) {
    debugPrint("Could not load env file: $e");
  }

  try {
    // A small delay helps Web stability
    await Future.delayed(const Duration(milliseconds: 200));
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error getting available cameras: $e');
    cameras = [];
  }

  runApp(const PetSpectorApp());
}

class PetSpectorApp extends StatelessWidget {
  const PetSpectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PetSpector',
      theme: ThemeData(
        primaryColor: const Color(0xFF3F7795), // theme color
        fontFamily: 'Poppins', // font for the app
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F7795))
            .copyWith(
              // Ensure primary color is used across the app
              primary: const Color(0xFF3F7795),
            ),
      ),
      debugShowCheckedModeBanner: false,
      // Use the prefixed User object (fb_auth.User) to check authentication state
      home: StreamBuilder<fb_auth.User?>(
        stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Show splash screen while checking auth state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }
          // If user is logged in, go to home screen, otherwise go to login
          if (snapshot.hasData && snapshot.data != null) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/signup': (context) => SignUpPage(),
        '/scan': (context) => const CamScanScreen(),
        '/admin': (context) => const AdminHistoryScreen(),
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // This splash screen now acts as the loading screen while checking Firebase state
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            // NOTE: Ensure 'assets/images/ps_icon.png' exists in your assets folder
            Image.asset('assets/images/ps_icon.png', height: 120),
            const SizedBox(height: 20),
            // App name
            Text(
              "PetSpector",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 10),
            // Tagline
            Text(
              "Smarter Care for Smarter Owners",
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Color(0xFF3F7795)),
          ],
        ),
      ),
    );
  }
}

class AdminHistoryScreen extends StatefulWidget {
  const AdminHistoryScreen({super.key});

  @override
  State<AdminHistoryScreen> createState() => _AdminHistoryScreenState();
}

class _AdminHistoryScreenState extends State<AdminHistoryScreen> {
  // LOGOUT LOGIC
  Future<void> _handleLogout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF3F7795);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: StreamBuilder<List<QuerySnapshot>>(
        stream: Rx.combineLatest2(
          FirebaseFirestore.instance.collection('scans').snapshots(),
          FirebaseFirestore.instance.collection('mood_analysis').snapshots(),
          (QuerySnapshot breedSnap, QuerySnapshot moodSnap) => [breedSnap, moodSnap],
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          // 1. Process Data
          final List<DocumentSnapshot> allDocs = [
            ...snapshot.data![0].docs,
            ...snapshot.data![1].docs,
          ];

          allDocs.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>?;
            final dataB = b.data() as Map<String, dynamic>?;
            final Timestamp t1 = dataA?['timestamp'] ?? Timestamp.fromMillisecondsSinceEpoch(0);
            final Timestamp t2 = dataB?['timestamp'] ?? Timestamp.fromMillisecondsSinceEpoch(0);
            return t2.compareTo(t1);
          });

          // 2. Build UI
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- HEADER ROW (Title + Buttons) ---
                Row(
                  children: [
                    Text(
                      "Admin Dashboard",
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    
                    // PRINT BUTTON
                    ElevatedButton.icon(
                      onPressed: allDocs.isEmpty ? null : () => _printHistory(allDocs),
                      icon: const Icon(Icons.print, size: 18, color: Colors.white),
                      label: const Text("Print", style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // LOGOUT BUTTON
                    OutlinedButton.icon(
                      onPressed: () => _handleLogout(context),
                      icon: const Icon(Icons.logout, size: 18, color: Colors.redAccent),
                      label: const Text("Logout", style: TextStyle(color: Colors.redAccent)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),

                // --- TABLE CARD ---
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: allDocs.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child: Text("No records found."),
                          ),
                        )
                      : Theme(
                          data: Theme.of(context).copyWith(
                            cardTheme: const CardThemeData(elevation: 0, color: Colors.transparent),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: PaginatedDataTable(
                              header: const Text("User Analysis History"),
                              rowsPerPage: 10,
                              columns: const [
                                DataColumn(label: Text("User", style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("Email", style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("Type", style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("Result", style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("Date", style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("Action", style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              source: _HistoryDataSource(allDocs, context),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HistoryDataSource extends DataTableSource {
  final List<DocumentSnapshot> docs;
  final BuildContext context;
  _HistoryDataSource(this.docs, this.context);

@override
DataRow? getRow(int index) {
  if (index >= docs.length) return null;
  final doc = docs[index];
  final data = doc.data() as Map<String, dynamic>;

  // IMPROVED LOGIC: Check for _type OR the existence of 'mood' field
  final bool isMood = data['_type'] == 'mood' || data.containsKey('mood');
  
  // Title logic
  final String resultTitle = isMood
      ? (data['mood'] ?? 'Mood Analysis')
      : (data['result'] ?? 'Unknown Pet');
      
  // Score logic
  final String score = isMood
      ? "${data['confidence'] ?? 0}%"
      : "${data['accuracy'] ?? 0}%";

    // User Name logic
    String fullName = "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();
    if (fullName.isEmpty) fullName = "Anonymous User";

    // Date Logic
    String dateStr = "N/A";
    if (data['timestamp'] != null) {
      DateTime dt = (data['timestamp'] as Timestamp).toDate();
      dateStr = "${dt.day}/${dt.month}/${dt.year}";
    }


    final Color themeColor = isMood ? const Color(0xFF6C63FF) : Colors.orange.shade800;
  return DataRow(
    cells: [
      DataCell(Text(fullName)),
      DataCell(Text(data['userEmail'] ?? 'N/A')),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: themeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: themeColor.withOpacity(0.5)),
          ),
          child: Text(
            isMood ? 'MOOD' : 'BREED',
            style: TextStyle(color: themeColor, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ),
        // RESULT (Name + Percentage)
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(resultTitle, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(score, style: TextStyle(fontSize: 11, color: themeColor)),
            ],
          ),
        ),
        DataCell(Text(dateStr)),
        // ACTIONS
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.visibility, color: Colors.blueGrey[700]),
                onPressed: () => _showDetailsSheet(context, data),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                onPressed: () => _confirmDelete(context, doc.id, data['_type'] ?? 'breed'),
              ),
            ],
          ),
        ),
      ],
    );
  }

    @override

  bool get isRowCountApproximate => false;

  @override

  int get rowCount => docs.length;

  @override

  int get selectedRowCount => 0;

Future<void> _confirmDelete(BuildContext context, String docId, String type) async {
  // Determine which collection to delete from based on the '_type' field
  String collectionName = (type == 'mood') ? 'mood_analysis' : 'scans';

  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Confirm Delete"),
      content: Text("Are you sure you want to delete this $type record?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async {
            await FirebaseFirestore.instance
                .collection(collectionName)
                .doc(docId)
                .delete();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Deleted from $collectionName")),
            );
          },
          child: const Text("Delete", style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

void _showDetailsSheet(BuildContext context, Map<String, dynamic> data) {
  bool isBreed = data['_type'] == 'breed';

  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        insetPadding: const EdgeInsets.all(20), // Margin from screen edges
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8, // Max 80% height
            maxWidth: 500, // Good for web or large tablets
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- HEADER ---
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isBreed ? "Breed Analysis" : "Mood Analysis",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3F7795),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // --- SCROLLABLE CONTENT ---
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: isBreed 
                      ? _buildScanDetailContent(data) 
                      : _buildMoodDetailContent(data),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}



Widget _buildScanDetailContent(Map<String, dynamic> data) {
  final List<dynamic> matches = data['matches'] ?? [];
  final int accuracyInt = data['accuracy'] ?? 0;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // --- IMAGE SECTION ---
      if (data['imageUrl'] != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.network(
            data['imageUrl'],
            height: 300,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 200,
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image, size: 50),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],

      // --- BREED & DESCRIPTION ---
      Text(
        data['result'] ?? 'Unknown Breed',
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
        Text(
          (data['type'] ?? 'Pet').toString().toUpperCase(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey[300],
          ),
        ),
      if (data['description'] != null)
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            data['description'],
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[700],
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ),

      const SizedBox(height: 30),

      // --- 2. MULTI-SEGMENT DONUT CHART WITH CENTER TEXT ---
      Center(
        child: SizedBox(
          height: 200, // Increased slightly to give text more breathing room
          child: matches.isNotEmpty 
            ? Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 60,
                      sections: matches.map((m) {
                        final colorStr = (m['color'] as String).replaceFirst('#', '0xFF');
                        return PieChartSectionData(
                          color: Color(int.parse(colorStr)),
                          value: (m['percentage'] as num).toDouble(),
                          title: '',
                          radius: 30,
                        );
                      }).toList(),
                    ),
                  ),
                  // THE CENTER TEXT
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "$accuracyInt%",
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3F7795),
                        ),
                      ),
                      Text(
                        "Confidence",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : _buildConfidenceGraph(accuracyInt, const Color(0xFF3F7795)),
        ),
      ),

      const SizedBox(height: 30),

      // --- 3. BREED ANALYSIS TILES ---
      if (matches.isNotEmpty) ...[
        const Text(
          "Breed Analysis",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...matches.map((m) => _buildBreedMatchTile(m as Map<String, dynamic>)),
        const SizedBox(height: 25),
      ],

      // --- INFO CARDS ---
      _buildInfoCard(
        title: "Common Allergies",
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFFFF4F2),
        iconColor: Colors.redAccent,
        child: Text(data['allergies'] ?? "No allergy data saved."),
      ),
      const SizedBox(height: 16),
      _buildInfoCard(
        title: "Care Tips",
        icon: Icons.lightbulb_outline_rounded,
        color: const Color(0xFFF0F9F1),
        iconColor: Colors.green,
        child: Text(data['care'] ?? "No care tips saved."),
      ),
      
      const SizedBox(height: 30),

      // --- CLOSE BUTTON ---
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F7795),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          child: const Text("Close", style: TextStyle(color: Colors.white)),
        ),
      ),
    ],
  );
}

Widget _buildBreedMatchTile(Map<String, dynamic> match) {
  final String breedName = match['breed']?.toString() ?? 'Unknown';
  final String hexColor = match['color']?.toString() ?? '#3F7795';
  final colorStr = hexColor.replaceFirst('#', '0xFF');
  final Color breedColor = Color(int.parse(colorStr));
  final num percentage = match['percentage'] ?? 0;

  // Helper function to launch the search
  Future<void> launchSearch() async {
  // Use Uri.https to safely encode the breed name for the URL
  final Uri url = Uri.https('www.google.com', '/search', {
    'q': '$breedName pet breed info',
  });

  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } else {
    // Fallback if the browser can't be opened
    debugPrint('Could not launch $url');
  }
}

  return InkWell(
    onTap: launchSearch, // Tap to search!
    borderRadius: BorderRadius.circular(15),
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, 
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 45,
                width: 45,
                child: CircularProgressIndicator(
                  value: percentage / 100,
                  strokeWidth: 4,
                  color: breedColor,
                  backgroundColor: Colors.grey.shade100,
                ),
              ),
              Icon(Icons.pets, size: 18, color: breedColor.withOpacity(0.6)),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  breedName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 15,
                    color: Color(0xFF2D3142),
                  ),
                  softWrap: true, // Allows text to wrap to the lower part
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      "$percentage% Match",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "• Tap to learn more",
                      style: TextStyle(color: Colors.blue[300], fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.open_in_new, size: 16, color: Colors.grey[300]),
        ],
      ),
    ),
  );
}

  Widget _buildMoodDetailContent(Map<String, dynamic> data) {
    final int confidenceInt = data['confidence'] ?? 0;
    final double confidenceDouble = confidenceInt / 100.0;

    // Mood color mapping
    Color moodColor = _getMoodColor(data['mood'] ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- MEDIA SECTION ---
        // --- MEDIA SECTION ---
        if (data['mediaUrl'] != null) ...[
          GestureDetector(
            onTap: () {
              if (data['mediaUrl'].contains('.mp4')) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        FullscreenVideoPlayer(url: data['mediaUrl']),
                  ),
                );
              }
            },
            child: Container(
              height: 250, // Slightly shorter to save space
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                image: !data['mediaUrl'].contains('.mp4')
                    ? DecorationImage(
                        image: NetworkImage(data['mediaUrl']),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: data['mediaUrl'].contains('.mp4')
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            color: Colors.white,
                            size: 80,
                          ),
                          SizedBox(height: 10),
                          Text(
                            "Tap to Play Video",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 20),
        ],

        // --- MOOD BADGE ---
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            // Added a constraint to ensure the badge doesn't try to be wider than the screen
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: moodColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: moodColor, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mood, color: moodColor, size: 32),
                const SizedBox(width: 12),
                // Wrap the text in Flexible to prevent the 320px overflow error
                Flexible(
                  child: Text(
                    data['mood'] ?? 'Unknown Mood',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: moodColor,
                    ),
                    overflow: TextOverflow
                        .ellipsis, // Adds "..." if the text is too long
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // --- CONFIDENCE SECTION ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Confidence Level",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            Text(
              "$confidenceInt%",
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3F7795),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: confidenceDouble,
            backgroundColor: const Color(0xFFEEEEEE),
            color: const Color(0xFF3F7795),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 25),

        // --- INFO CARDS ---
        _buildInfoCard(
          title: "Body Language",
          icon: Icons.gesture,
          color: const Color(0xFFE3F2FD),
          iconColor: Colors.blue,
          child: Text(data['bodyLanguage'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          title: "Behavior Analysis",
          icon: Icons.psychology,
          color: const Color(0xFFF3E5F5),
          iconColor: Colors.purple,
          child: Text(data['behaviorAnalysis'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          title: "Positive Signs",
          icon: Icons.sentiment_very_satisfied,
          color: const Color(0xFFF0F9F1),
          iconColor: Colors.green,
          child: Text(data['positiveSigns'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          title: "Concerns",
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFFFF4F2),
          iconColor: Colors.redAccent,
          child: Text(data['concerns'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          title: "Recommendations",
          icon: Icons.lightbulb_outline_rounded,
          color: const Color(0xFFFFF9E6),
          iconColor: Colors.orange,
          child: Text(data['recommendations'] ?? ""),
        ),
        const SizedBox(height: 30),

        // --- CLOSE BUTTON ---
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3F7795),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: const Text("Close", style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }
// Helper for Information Cards
Widget _buildInfoCard({
  required String title,
  required IconData icon,
  required Color color,
  required Color iconColor,
  required Widget child,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: iconColor)),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

// Mood Color Logic
Color _getMoodColor(String mood) {
  final m = mood.toLowerCase();
  if (m.contains('happy') || m.contains('relaxed')) return Colors.green;
  if (m.contains('stressed') || m.contains('anxious')) return Colors.orange;
  if (m.contains('aggressive') || m.contains('angry')) return Colors.red;
  return const Color(0xFF6C63FF); // Default Purple
}

// Confidence Graph Fallback (if PieChart is not used)
Widget _buildConfidenceGraph(int accuracy, Color color) {
  return Column(
    children: [
      CircularProgressIndicator(
        value: accuracy / 100,
        strokeWidth: 8,
        color: color,
        backgroundColor: color.withOpacity(0.1),
      ),
      const SizedBox(height: 10),
      Text("$accuracy%", style: TextStyle(fontWeight: FontWeight.bold, color: color)),
    ],
  );
}
}

Future<void> _printHistory(List<DocumentSnapshot> allDocs) async {
  final pdf = pw.Document();
  final primaryColor = PdfColor.fromInt(0xFF3F7795); // Your Admin Primary Color
  final accentColor = PdfColor.fromInt(0xFF6C63FF);  // Your Mood Purple

  final headers = ['User', 'Email', 'Type', 'Result', 'Score', 'Date'];

  final data = allDocs.map((doc) {
    final d = doc.data() as Map<String, dynamic>;
    final bool isMood = d['_type'] == 'mood' || d.containsKey('mood');
    DateTime? dt = (d['timestamp'] as Timestamp?)?.toDate();
    String dateStr = dt != null ? "${dt.day}/${dt.month}/${dt.year}" : "N/A";

    return [
      "${d['firstName'] ?? ''} ${d['lastName'] ?? ''}".trim(),
      d['userEmail'] ?? 'N/A',
      isMood ? 'MOOD' : 'BREED',
      isMood ? (d['mood'] ?? 'N/A') : (d['result'] ?? 'N/A'),
      isMood ? "${d['confidence'] ?? 0}%" : "${d['accuracy'] ?? 0}%",
      dateStr,
    ];
  }).toList();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context context) => [
        // --- MODERN HEADER ---
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("PETSPECTOR", 
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                pw.Text("Admin Analysis History Report", 
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text("Generated on: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}"),
                pw.Text("Total Records: ${allDocs.length}"),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Divider(thickness: 2, color: primaryColor),
        pw.SizedBox(height: 20),

        // --- MODERN TABLE ---
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: data,
          // Header Styling
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
          headerDecoration: pw.BoxDecoration(color: primaryColor, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2))),
          
          // Cell Styling
          cellStyle: const pw.TextStyle(fontSize: 7),
          cellAlignment: pw.Alignment.centerLeft,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          
          // Borders & Alternating Colors (Modern Zebra Stripe)
          border: null,
          rowDecoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))
          ),
          oddRowDecoration: pw.BoxDecoration(color: PdfColors.grey100),

          cellAlignments: {
            2: pw.Alignment.center,
            4: pw.Alignment.center,
            5: pw.Alignment.center,
          },
        ),
        
        // --- FOOTER ---
        pw.SizedBox(height: 30),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text("End of Report", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500)),
        )
      ],
    ),
  );

  await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = fb_auth.FirebaseAuth.instance;

  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _loginWithEmail() async {
    setState(() => _isLoading = true);

    try {
      // 1. Log in with Firebase Auth
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;

      // 2. Check if Email is Verified
      if (user != null) {
        // 3. Fetch the role from Firestore
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        // Default to 'user' if the field is missing
        String role = userDoc.data()?['role'] ?? 'user';

        if (!mounted) return;

        // 4. Navigate based on the role
        if (role == 'admin') {
          Navigator.pushReplacementNamed(context, '/admin');
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // 5. Handle unverified email
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please verify your email before logging in.'),
            backgroundColor: Colors.red,
          ),
        );
        await _auth.signOut();
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      // 6. Handle Firebase Errors
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found with this email.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address format.';
          break;
        default:
          errorMessage = 'Login failed. Please try again.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    } finally {
      // 7. Always stop the loading spinner
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your email to reset password."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password reset email sent! Check your inbox."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to send reset email. Try again."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 1. Helper method (Removed @override)
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required double scale,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : false,
      style: TextStyle(fontSize: 16 * scale),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 14 * scale),
        prefixIcon: Icon(
          icon,
          color: const Color(0xFF3F7795),
          size: 22 * scale,
        ),
        filled: true,
        fillColor: const Color(0xFFF0F7F9),
        contentPadding: EdgeInsets.symmetric(
          vertical: 18 * scale,
          horizontal: 15 * scale,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  size: 20 * scale,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
      ),
    );
  }

  // 2. Main Build Method
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    // Scale text and icons slightly on larger screens
    final double scaleFactor = screenWidth > 600 ? 1.15 : 1.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Container(
            // Limit form width to 450px for a professional Web look
            constraints: const BoxConstraints(maxWidth: 450),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo and Branding
                  Image.asset(
                    'assets/images/ps_icon.png',
                    height: 100 * scaleFactor,
                  ),
                  SizedBox(height: 20 * scaleFactor),
                  Text(
                    "PetSpector",
                    style: TextStyle(
                      fontSize: 32 * scaleFactor,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF3F7795),
                    ),
                  ),
                  Text(
                    "Login to your account",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14 * scaleFactor,
                    ),
                  ),
                  SizedBox(height: 40 * scaleFactor),

                  // Styled TextFields
                  _buildTextField(
                    controller: _emailController,
                    label: "Email",
                    icon: Icons.email_outlined,
                    scale: scaleFactor,
                  ),
                  SizedBox(height: 15 * scaleFactor),
                  _buildTextField(
                    controller: _passwordController,
                    label: "Password",
                    icon: Icons.lock_outline,
                    isPassword: true,
                    scale: scaleFactor,
                  ),

                  // Forgot Password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resetPassword,
                      child: Text(
                        "Forgot Password?",
                        style: TextStyle(
                          color: const Color(0xFF3F7795),
                          fontWeight: FontWeight.w600,
                          fontSize: 14 * scaleFactor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20 * scaleFactor),

                  // Action Buttons
                  _isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _loginWithEmail,
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(
                              double.infinity,
                              55 * scaleFactor,
                            ),
                            backgroundColor: const Color(0xFF3F7795),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: Text(
                            "Login",
                            style: TextStyle(
                              fontSize: 18 * scaleFactor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                  SizedBox(height: 20 * scaleFactor),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(fontSize: 14 * scaleFactor),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/signup'),
                        child: Text(
                          "Sign Up",
                          style: TextStyle(
                            color: const Color(0xFF3F7795),
                            fontWeight: FontWeight.bold,
                            fontSize: 14 * scaleFactor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
