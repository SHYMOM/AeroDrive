import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../main.dart' as app_main;

/// A premium, custom-designed screen for viewing system diagnostics or reporting crashes.
///
/// If [error] is provided, the screen displays in "Crash Report" mode with red highlights,
/// allowing the user to view the critical error details and restart the app.
/// Otherwise, it displays in "System Diagnostics" mode with cyan highlights.
class DebugErrorScreen extends StatefulWidget {

  const DebugErrorScreen({
    super.key,
    this.error,
    this.stack,
    required this.logs,
  });
  final Object? error;
  final StackTrace? stack;
  final List<String> logs;

  @override
  State<DebugErrorScreen> createState() => _DebugErrorScreenState();
}

class _DebugErrorScreenState extends State<DebugErrorScreen> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSending = false;
  bool _isLogsExpanded = false;

  bool get _isCrashMode => widget.error != null;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// Copies error, stack trace, and logs to the system clipboard.
  void _copyToClipboard() {
    final buffer = StringBuffer();
    buffer.writeln('=== AERO DRIVE DIAGNOSTICS ===');
    buffer.writeln('Mode: ${_isCrashMode ? "CRASH REPORT" : "MANUAL DIAGNOSTICS"}');
    buffer.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
    
    if (_isCrashMode) {
      buffer.writeln('\nException: ${widget.error}');
      buffer.writeln('\nStack Trace:\n${widget.stack}');
    }

    if (_commentController.text.trim().isNotEmpty) {
      buffer.writeln('\nUser Comments:\n${_commentController.text.trim()}');
    }

    buffer.writeln('\n=== SYSTEM LOGS ===');
    for (final log in widget.logs) {
      buffer.writeln(log);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.success),
            SizedBox(width: 8),
            Text('Logs copied to clipboard'),
          ],
        ),
        backgroundColor: AppColors.surfaceElevated,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Simulates sending the diagnostics/crash report.
  Future<void> _sendReport() async {
    if (_isSending) return;

    setState(() {
      _isSending = true;
    });

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1500));

    if (!mounted) return;

    setState(() {
      _isSending = false;
    });

    // Show custom success dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.offline_pin_outlined,
          color: _isCrashMode ? AppColors.tertiary : AppColors.secondary,
          size: 48,
        ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),
        title: const Text('Report Submitted'),
        content: const Text(
          'Thank you for helping us improve AeroDrive! The diagnostic payload and details have been prepared for sending.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (!_isCrashMode) {
                Navigator.of(context).pop(); // Go back to settings
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Restarts the application programmatically by re-running the main entrypoint.
  void _restartApp() {
    app_main.main();
  }

  /// Helper to color code terminal logs.
  Color _getLogColor(String line) {
    if (line.contains('[ERROR]')) return AppColors.error;
    if (line.contains('[WARNING]')) return AppColors.warning;
    if (line.contains('[INFO]')) return AppColors.secondary;
    return AppColors.onSurface.withValues(alpha: 0.85);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _isCrashMode ? AppColors.error : AppColors.secondary;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accentColor.withValues(alpha: 0.05),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                
                // Animated header icon
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withValues(alpha: 0.2), width: 1.5),
                    ),
                    child: Icon(
                      _isCrashMode ? Icons.gpp_bad_outlined : Icons.bug_report_outlined,
                      color: accentColor,
                      size: 40,
                    ),
                  )
                  .animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .scale(
                    end: const Offset(1.08, 1.08),
                    duration: 1200.ms,
                    curve: Curves.easeInOut,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Page Title
                Text(
                  _isCrashMode ? 'AeroDrive Crash Report' : 'AeroDrive Diagnostics',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Mode description
                Text(
                  _isCrashMode
                      ? 'The application encountered an unexpected runtime exception and has been paused safely.'
                      : 'System diagnostics engine active. You can view, copy, or send the system execution logs below.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                
                const SizedBox(height: 24),

                // Error Details Card (if in Crash Mode)
                if (_isCrashMode) ...[
                  Card(
                    color: AppColors.surface,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Exception Caught',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            widget.error.toString(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0),
                  const SizedBox(height: 16),
                ],

                // User Input Comment Field
                Text(
                  'What were you doing when this happened? (Optional)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g., Opening settings, trying to view video, connecting account...',
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: accentColor, width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Expandable Log Viewer
                Card(
                  color: AppColors.surface,
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.terminal_outlined,
                          color: _isLogsExpanded ? accentColor : AppColors.onSurfaceVariant,
                        ),
                        title: const Text(
                          'Console Log Buffer',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${widget.logs.length} statements cached',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Icon(
                          _isLogsExpanded ? Icons.expand_less : Icons.expand_more,
                          color: AppColors.onSurfaceVariant,
                        ),
                        onTap: () {
                          setState(() {
                            _isLogsExpanded = !_isLogsExpanded;
                          });
                        },
                      ),
                      if (_isLogsExpanded) ...[
                        const Divider(height: 1),
                        Container(
                          height: 250,
                          width: double.infinity,
                          color: const Color(0xFF070814),
                          child: widget.logs.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No logs in buffer.',
                                    style: TextStyle(fontFamily: 'monospace', color: AppColors.onSurfaceVariant),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: widget.logs.length + (_isCrashMode ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == widget.logs.length && _isCrashMode) {
                                      // Append stack trace at the end of the scroll view for easy debugging
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(
                                          '=== STACK TRACE ===\n${widget.stack}',
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      );
                                    }
                                    final logLine = widget.logs[index];
                                    return Text(
                                      logLine,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: _getLogColor(logLine),
                                        height: 1.4,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ],
                  ),
                ).animate().fade(duration: 400.ms, delay: 100.ms),

                const SizedBox(height: 32),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyToClipboard,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy Log'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accentColor,
                          side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSending ? null : _sendReport,
                        icon: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: Text(_isSending ? 'Sending...' : 'Send Report'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Restart / Return Button
                FilledButton.icon(
                  onPressed: _isCrashMode ? _restartApp : () => Navigator.of(context).pop(),
                  icon: Icon(_isCrashMode ? Icons.refresh : Icons.arrow_back),
                  label: Text(_isCrashMode ? 'Restart AeroDrive' : 'Return to Settings'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surfaceVariant,
                    foregroundColor: AppColors.onSurface,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppColors.outline),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
