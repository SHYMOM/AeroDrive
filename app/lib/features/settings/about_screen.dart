import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchUrl(BuildContext context, String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: const Text('About AeroDrive'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        children: [
          // App Logo / Info
          Center(
            child: Column(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.blueAccent, Colors.purpleAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: const Icon(Icons.cloud, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  'AeroDrive',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0-alpha',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // About Application
          Card(
            color: Colors.grey[900],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.only(bottom: 24),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.info_outline, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Text('About Application', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'AeroDrive is an advanced, ultra-secure, and decentralized cloud storage client powered directly by the Telegram TDLib backend. It provides users with unlimited storage by harnessing Telegram channels as a backend file system, wrapped in a beautiful and highly functional Material 3 interface.',
                    style: TextStyle(height: 1.5, color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          // About Developer
          Card(
            color: Colors.grey[900],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.only(bottom: 24),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.person_outline, color: Colors.purpleAccent),
                      SizedBox(width: 8),
                      Text('About Developer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipOval(
                        child: Image.network(
                          'https://avatars.githubusercontent.com/u/130169485',
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 70,
                            height: 70,
                            color: Colors.white10,
                            child: const Icon(Icons.person, size: 35, color: Colors.white30),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SHEIKH SHYMOM ISLAM',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Computer Science Student & App Developer',
                              style: TextStyle(color: Colors.grey[400], fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '👋 Hey there! I\'m Shymom... A CSE student, app dev enthusiast, and tech explorer with a knack for crafting solutions and diving into new tech.',
                    style: TextStyle(height: 1.5, color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.code, color: Colors.blueAccent),
                        label: const Text('GitHub', style: TextStyle(color: Colors.blueAccent)),
                        onPressed: () => _launchUrl(context, 'https://github.com/SHYMOM'),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.facebook, color: Colors.blueAccent),
                        label: const Text('Facebook', style: TextStyle(color: Colors.blueAccent)),
                        onPressed: () => _launchUrl(context, 'https://www.facebook.com/Sheikh.Shymom'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Action Buttons / Links
          Card(
            color: Colors.grey[900],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ListTile(
                  leading: const Icon(Icons.update, color: Colors.white70),
                  title: const Text('Check for Updates', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('You are on the latest version', style: TextStyle(color: Colors.white70)),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AeroDrive is up to date!')));
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                ListTile(
                  leading: const Icon(Icons.code, color: Colors.white70),
                  title: const Text('GitHub Repository', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('View the source code', style: TextStyle(color: Colors.white70)),
                  onTap: () => _launchUrl(context, 'https://github.com/SHYMOM/AeroDrive'),
                ),
                const Divider(height: 1, color: Colors.white10),
                ListTile(
                  leading: const Icon(Icons.bug_report, color: Colors.white70),
                  title: const Text('Report a Bug', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Submit an issue on GitHub', style: TextStyle(color: Colors.white70)),
                  onTap: () => _launchUrl(context, 'https://github.com/SHYMOM/AeroDrive/issues'),
                ),
                const Divider(height: 1, color: Colors.white10),
                ListTile(
                  leading: const Icon(Icons.favorite, color: Colors.white70),
                  title: const Text('Donate', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Support the ongoing development', style: TextStyle(color: Colors.white70)),
                  onTap: () => _launchUrl(context, 'https://github.com/sponsors/SHYMOM'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
}
