/// Stub implementation for non-web platforms.
/// The web implementation uses dart:html to trigger file downloads.

import 'dart:typed_data';

/// Download [bytes] as a file named [filename].
/// On non-web platforms, this is a no-op (the caller should use the OS
/// share sheet or save-to-gallery flow instead).
void downloadBytes(Uint8List bytes, String filename) {
  // No-op on native — use share_plus or printing package instead.
}
