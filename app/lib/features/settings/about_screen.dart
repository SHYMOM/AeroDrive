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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About AeroDrive'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        children: [
          // App Logo / Info
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.cloud, size: 60, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  'AeroDrive',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0-alpha',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),

          // About Application
          const Text('About Application', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
            'AeroDrive is an advanced, ultra-secure, and decentralized cloud storage client powered directly by the Telegram TDLib backend. It provides users with unlimited storage by harnessing Telegram channels as a backend file system, wrapped in a beautiful and highly functional Material 3 interface.',
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 24),

          // About Developer
          const Text('About Developer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
            'Developed with passion to push the limits of modern mobile and desktop application architecture. AeroDrive uses Rust for core crypto, Go for companion services, and Flutter for its dynamic UI engine.',
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 32),

          // Action Buttons
          ListTile(
            leading: const Icon(Icons.update),
            title: const Text('Check for Updates'),
            subtitle: const Text('You are on the latest version'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AeroDrive is up to date!')));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('GitHub Repository'),
            subtitle: const Text('View the source code'),
            onTap: () => _launchUrl(context, 'https://github.com/'), // Replace with actual URL later
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Report a Bug'),
            subtitle: const Text('Submit an issue on GitHub'),
            onTap: () => _launchUrl(context, 'https://github.com/issues'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.favorite),
            title: const Text('Donate'),
            subtitle: const Text('Support the ongoing development'),
            onTap: () => _launchUrl(context, 'https://github.com/sponsors'),
          ),
        ],
      ),
    );
  }
}
