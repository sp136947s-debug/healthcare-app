import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'config.dart';

void main() => runApp(const NidanApp());

class NidanApp extends StatelessWidget {
  const NidanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NIDAN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF7FBFA),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _text = TextEditingController();
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  final _uuid = const Uuid();
  late String sessionId;

  bool listening = false;
  bool busy = false;
  String selectedLanguage = 'hi-IN';
  String answer = '';

  final languages = const {
    'hi-IN': 'हिन्दी',
    'en-IN': 'English',
    'bn-IN': 'বাংলা',
    'ta-IN': 'தமிழ்',
    'te-IN': 'తెలుగు',
    'mr-IN': 'मराठी',
    'gu-IN': 'ગુજરાતી',
    'kn-IN': 'ಕನ್ನಡ',
    'ml-IN': 'മലയാളം',
    'pa-IN': 'ਪੰਜਾਬੀ',
  };

  @override
  void initState() {
    super.initState();
    sessionId = _uuid.v4();
    _tts.setSpeechRate(0.45);
  }

  Future<void> listen() async {
    if (listening) {
      await _speech.stop();
      setState(() => listening = false);
      return;
    }

    final available = await _speech.initialize();
    if (!available) {
      _show('Speech recognition is not available on this device.');
      return;
    }

    setState(() => listening = true);
    await _speech.listen(
      localeId: selectedLanguage,
      onResult: (result) {
        setState(() => _text.text = result.recognizedWords);
        if (result.finalResult) {
          setState(() => listening = false);
        }
      },
    );
  }

  Future<void> askNidan() async {
    final message = _text.text.trim();
    if (message.isEmpty || busy) return;

    setState(() => busy = true);
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'message': message,
          'language': selectedLanguage,
        }),
      );

      if (response.statusCode >= 400) {
        throw Exception(response.body);
      }

      final data = jsonDecode(response.body);
      setState(() => answer = data['answer'] ?? '');
      await speak(answer);
    } catch (e) {
      _show('Backend connect nahi ho raha. Check that FastAPI is running.');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    final locale = selectedLanguage.replaceAll('-', '_');
    await _tts.setLanguage(locale);
    await _tts.speak(text);
  }

  Future<void> nearby() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _show('Location permission is needed for nearby healthcare.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final uri = Uri.parse(
        '$apiBaseUrl/healthcare?latitude=${pos.latitude}&longitude=${pos.longitude}&language=${selectedLanguage.substring(0, 2)}',
      );
      final response = await http.get(uri);
      final data = jsonDecode(response.body);
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HealthcarePage(
            results: List<Map<String, dynamic>>.from(
              data['results'] ?? const [],
            ),
            message: data['message'],
          ),
        ),
      );
    } catch (_) {
      _show('Nearby healthcare load nahi ho paaya.');
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'NIDAN',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedLanguage,
              items: languages.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => selectedLanguage = v);
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const SizedBox(height: 8),
            Center(
              child: CircleAvatar(
                radius: 46,
                child: Text('🩺', style: TextStyle(fontSize: 42)),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Aapko kya dikkat hai?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Boliye. NIDAN aapki baat samajhkar next step batayega.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: listen,
              icon: Icon(listening ? Icons.stop : Icons.mic),
              label: Text(listening ? 'SUN RAHA HOON...' : 'BOLEIN'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Ya yahan likhein...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: busy ? null : askNidan,
              child: Text(busy ? 'Soch raha hai...' : 'NIDAN SE PUCHHEIN'),
            ),
            if (answer.isNotEmpty) ...[
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('NIDAN', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(answer, style: const TextStyle(fontSize: 17, height: 1.45)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => speak(answer),
                        icon: const Icon(Icons.volume_up),
                        label: const Text('SUNAAYEIN'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: nearby,
                    icon: const Icon(Icons.location_on),
                    label: const Text('NEARBY HEALTHCARE'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TriagePage()),
                    ),
                    icon: const Icon(Icons.health_and_safety),
                    label: const Text('SAFETY CHECK'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const AbhaDialog(),
                    ),
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('ABHA HELP'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReportHelpPage(onSpeak: speak),
                ),
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('REPORT / PRESCRIPTION HELP'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FeedbackPage(
                    sessionId: sessionId,
                    language: selectedLanguage,
                  ),
                ),
              ),
              icon: const Icon(Icons.feedback_outlined),
              label: const Text('FEEDBACK'),
            ),
            const SizedBox(height: 18),
            const Text(
              'Important: NIDAN diagnosis nahi karta. Emergency me chatbot par wait na karein; turant emergency medical help lein.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class HealthcarePage extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final String? message;

  const HealthcarePage({super.key, required this.results, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Healthcare')),
      body: results.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message ?? 'No live facilities found.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: results.length,
              itemBuilder: (_, i) {
                final p = results[i];
                return Card(
                  child: ListTile(
                    title: Text(p['name'] ?? 'Healthcare facility'),
                    subtitle: Text(
                      '${p['address'] ?? ''}\n'
                      '${p['distance_km'] ?? '?'} km'
                      '${p['open_now'] == true ? ' • Open now' : ''}',
                    ),
                    trailing: p['maps_url'] != null
                        ? IconButton(
                            icon: const Icon(Icons.directions),
                            onPressed: () => launchUrl(
                              Uri.parse(p['maps_url']),
                              mode: LaunchMode.externalApplication,
                            ),
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }
}

class TriagePage extends StatelessWidget {
  const TriagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Check')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Agar inme se koi serious problem hai, wait mat karein:',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          for (final item in [
            'Severe chest pain',
            'Severe breathing difficulty',
            'Unconsciousness',
            'Seizure',
            'Heavy bleeding',
            'Stroke-like symptoms',
          ])
            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text(item),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Emergency'),
                content: const Text(
                  'Turant local emergency medical service ya nearest emergency department se help lein. Akela na rahein.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.emergency),
            label: const Text('EMERGENCY GUIDANCE'),
          ),
        ],
      ),
    );
  }
}

class AbhaDialog extends StatelessWidget {
  const AbhaDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ABHA Help'),
      content: const Text(
        'NIDAN ABHA ke baare me simple information aur official process samjhane me help kar sakta hai. '
        'MVP me live ABHA account linking ya record access fake nahi kiya gaya hai. '
        'Official ABDM channel se hi account/record status verify karein.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Samajh gaya'),
        ),
      ],
    );
  }
}

class ReportHelpPage extends StatefulWidget {
  final Future<void> Function(String) onSpeak;
  const ReportHelpPage({super.key, required this.onSpeak});

  @override
  State<ReportHelpPage> createState() => _ReportHelpPageState();
}

class _ReportHelpPageState extends State<ReportHelpPage> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report / Prescription Help')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text(
              'Report ya prescription ka text yahan paste karein. NIDAN uska simple explanation de sakta hai.',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Report text...',
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('MAIN CHAT SE EXPLAIN KARAYEIN'),
            ),
          ],
        ),
      ),
    );
  }
}

class FeedbackPage extends StatefulWidget {
  final String sessionId;
  final String language;
  const FeedbackPage({super.key, required this.sessionId, required this.language});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int rating = 5;
  final comment = TextEditingController();
  bool sending = false;

  Future<void> send() async {
    setState(() => sending = true);
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/feedback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': widget.sessionId,
          'rating': rating,
          'comment': comment.text,
          'language': widget.language,
        }),
      );
      if (response.statusCode >= 400) throw Exception();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you! Feedback saved.')),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback save nahi hua.')),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('NIDAN kaisa laga?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: List.generate(5, (i) {
              final value = i + 1;
              return ChoiceChip(
                label: Text('$value ⭐'),
                selected: rating == value,
                onSelected: (_) => setState(() => rating = value),
              );
            }),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: comment,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Kya improve karna chahiye?',
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: sending ? null : send,
            child: Text(sending ? 'Saving...' : 'SUBMIT'),
          ),
        ],
      ),
    );
  }
}
