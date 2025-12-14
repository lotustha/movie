import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

// A StatefulWidget is used here to track and update the maximization state.
class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key});

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

// MODIFIED: Added 'with WindowListener' to correctly handle window events.
class _WindowButtonsState extends State<WindowButtons> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    // MODIFIED: Add 'this' as the listener.
    windowManager.addListener(this);
    // Check the initial state when the widget is first built.
    _checkInitialMaximizeState();
  }

  @override
  void dispose() {
    // MODIFIED: Remove 'this' as the listener.
    windowManager.removeListener(this);
    super.dispose();
  }

  // NEW: A separate function to check the initial state, as listeners only fire on change.
  void _checkInitialMaximizeState() async {
    _isMaximized = await windowManager.isMaximized();
    if (mounted) {
      setState(() {});
    }
  }

  // NEW: Override from WindowListener to handle the maximize event.
  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() {
        _isMaximized = true;
      });
    }
  }

  // NEW: Override from WindowListener to handle the restore/unmaximize event.
  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() {
        _isMaximized = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // This makes the entire widget draggable, functioning as a custom title bar.
    return DragToMoveArea(
      child: Container(
        height: 40, // Standard title bar height
        color: Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // This spacer pushes the buttons to the far right.
            const Spacer(),
            // Minimize Button
            _buildButton(
              icon: Icons.minimize_rounded,
              onPressed: () => windowManager.minimize(),
              tooltip: 'Minimize',
            ),
            // Maximize / Restore Button
            _buildButton(
              // The icon changes based on the window's maximization state.
              icon: _isMaximized
                  ? Icons.filter_none_rounded // Restore icon
                  : Icons.crop_square_rounded, // Maximize icon
              onPressed: () {
                if (_isMaximized) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              tooltip: _isMaximized ? 'Restore' : 'Maximize',
            ),
            // Close Button
            _buildButton(
              icon: Icons.close_rounded,
              onPressed: () => windowManager.close(),
              isCloseButton: true,
              tooltip: 'Close',
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  // Helper method to create consistently styled buttons.
  Widget _buildButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    bool isCloseButton = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 46,
        height: 32,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.zero, // Square corners for hover effect
            hoverColor: isCloseButton
                ? Colors.red.withOpacity(0.8)
                : Colors.white.withOpacity(0.1),
            child: Center(
              child: Icon(
                icon,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

