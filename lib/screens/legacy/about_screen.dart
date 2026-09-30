import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../widgets/branding.dart';

/// Original about page (extracted unchanged).
/// Adapter exposing the preserved about page under the name used by the
/// messaging app shell.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: AboutPage(),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<PackageInfo> _getPackageInfo() => PackageInfo.fromPlatform();

  Widget _sectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _getPackageInfo(),
      builder: (BuildContext context, AsyncSnapshot<PackageInfo> snapshot) {
        final String version = snapshot.hasData
            ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
            : '1.0.0+1';

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SmartBridgeLogo(size: 46),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SmartBridge',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Communication Assistant',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A communication assistant that pairs a blind person and a deaf person in one shared conversation, with speech-to-text and text-to-speech support.',
                    ),
                    const SizedBox(height: 12),
                    Text('Version: $version'),
                    const SizedBox(height: 4),
                    Text(
                      'Release date: April 15, 2026',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Designed for fast everyday communication support in classrooms, homes, and public spaces.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            _sectionCard(
              context: context,
              title: 'System Functions',
              children: const [
                Text('1. Voice messages turned into simple text.'),
                Text('2. Typed messages with a chosen emotion.'),
                Text('3. Spoken output through text-to-speech.'),
                Text('4. Accessibility customization and motion controls.'),
                Text('5. Friend codes to connect two people safely.'),
                Text('6. Local chat that works on the same Wi-Fi.'),
                Text('7. Optional internet messaging when the backend is configured.'),
              ],
            ),
            _sectionCard(
              context: context,
              title: 'Permissions and Privacy',
              children: const [
                Text(
                  '• Microphone access is required for voice messages.',
                ),
                Text(
                  '• Camera access is used only when you scan a friend\'s QR code.',
                ),
                Text('• Your conversations are stored locally on your device.'),
                Text('• Review app permissions anytime in Settings.'),
              ],
            ),
            _sectionCard(
              context: context,
              title: 'Terms Notice',
              children: const [
                Text(
                  'SmartBridge provides assistive output and may not always be perfectly accurate.',
                ),
                SizedBox(height: 6),
                Text(
                  'Do not rely on this app as the only source for medical, legal, emergency, safety-critical, or financial communication decisions.',
                ),
                SizedBox(height: 6),
                Text(
                  'By using SmartBridge, you agree to use it responsibly, maintain situational awareness, and verify critical information through qualified professionals when needed.',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

