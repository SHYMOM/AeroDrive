import 'package:shelf/shelf.dart' as shelf;
import 'package:xml/xml.dart';

class PropfindHandler {
  static Future<shelf.Response> handle(shelf.Request request) async {
    // 1. Read depth (0 = this folder only, 1 = this folder + children)
    final depth = request.headers['depth'] ?? '1';
    
    // 2. Parse XML to see what properties Windows Explorer is asking for
    final bodyStr = await request.readAsString();
    List<String> requestedProps = [];
    
    if (bodyStr.isNotEmpty) {
      try {
        final doc = XmlDocument.parse(bodyStr);
        final propNode = doc.findAllElements('prop', namespace: 'DAV:').firstOrNull ?? 
                         doc.findAllElements('D:prop').firstOrNull;
                         
        if (propNode != null) {
          requestedProps = propNode.children
              .whereType<XmlElement>()
              .map((e) => e.name.local)
              .toList();
        }
      } catch (_) {
        // Fallback to basic props if parsing fails
      }
    }

    if (requestedProps.isEmpty) {
      requestedProps = ['getcontentlength', 'getlastmodified', 'resourcetype', 'creationdate'];
    }

    // 3. Look up SQLite for the path (MOCK LOGIC)
    // Here we would query AeroDriveDatabase for the folder ID matching `request.url.path`
    // For now, we return a mock multistatus response
    
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="utf-8"');
    builder.element('D:multistatus', namespaces: {'DAV:': 'D'}, nest: () {
      
      // Self item
      builder.element('D:response', nest: () {
        builder.element('D:href', nest: '/${request.url.path}');
        builder.element('D:propstat', nest: () {
          builder.element('D:prop', nest: () {
            if (requestedProps.contains('resourcetype')) {
              builder.element('D:resourcetype', nest: () {
                builder.element('D:collection');
              });
            }
            if (requestedProps.contains('getlastmodified')) {
              builder.element('D:getlastmodified', nest: 'Mon, 01 Jan 2026 12:00:00 GMT');
            }
          });
          builder.element('D:status', nest: 'HTTP/1.1 200 OK');
        });
      });

      // If Depth == 1, iterate through child folders and files from SQLite
      if (depth == '1') {
        // Example mock file
        builder.element('D:response', nest: () {
          builder.element('D:href', nest: '/${request.url.path}/mock_file.txt');
          builder.element('D:propstat', nest: () {
            builder.element('D:prop', nest: () {
              if (requestedProps.contains('resourcetype')) {
                builder.element('D:resourcetype'); // Empty means file
              }
              if (requestedProps.contains('getcontentlength')) {
                builder.element('D:getcontentlength', nest: '1024');
              }
            });
            builder.element('D:status', nest: 'HTTP/1.1 200 OK');
          });
        });
      }
    });

    return shelf.Response(
      207, // Multi-Status
      body: builder.buildDocument().toXmlString(),
      headers: {'Content-Type': 'application/xml; charset=utf-8'},
    );
  }
}
