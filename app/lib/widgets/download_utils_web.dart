/// Web implementation — uses dart:html to trigger a file download.

import 'dart:html' as html;
import 'dart:typed_data';

/// Download [bytes] as a file named [filename] via the browser's download API.
void downloadBytes(Uint8List bytes, String filename) {
  final blob = html.Blob([bytes.toList()], 'image/png');
  final url = html.Url.createObjectUrl(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..click();
  html.Url.revokeObjectUrl(url);
}
