import 'package:flutter/material.dart';

class FileTypeIcon extends StatelessWidget {
  final String? mimeType;
  final String fileName;
  final double size;

  const FileTypeIcon({
    super.key,
    required this.mimeType,
    required this.fileName,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final type = (mimeType ?? '').toLowerCase();
    final ext = fileName.split('.').last.toLowerCase();

    IconData iconData = Icons.insert_drive_file;
    Color iconColor = Colors.grey;

    if (type.startsWith('image/') || ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      iconData = Icons.image;
      iconColor = Colors.blueAccent;
    } else if (type.startsWith('video/') || ['mp4', 'mkv', 'avi', 'mov'].contains(ext)) {
      iconData = Icons.movie;
      iconColor = Colors.purpleAccent;
    } else if (type.startsWith('audio/') || ['mp3', 'wav', 'ogg', 'flac'].contains(ext)) {
      iconData = Icons.audiotrack;
      iconColor = Colors.amber;
    } else if (type.contains('pdf') || ext == 'pdf') {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.redAccent;
    } else if (type.contains('word') || type.contains('document') || ['doc', 'docx'].contains(ext)) {
      iconData = Icons.description;
      iconColor = Colors.lightBlue;
    } else if (type.contains('excel') || type.contains('spreadsheet') || ['xls', 'xlsx', 'csv'].contains(ext)) {
      iconData = Icons.table_chart;
      iconColor = Colors.green;
    } else if (type.contains('presentation') || ['ppt', 'pptx'].contains(ext)) {
      iconData = Icons.slideshow;
      iconColor = Colors.orange;
    } else if (type.contains('zip') || type.contains('compressed') || ['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      iconData = Icons.folder_zip;
      iconColor = Colors.brown;
    } else if (type.contains('json') || type.contains('xml') || type.contains('html') || ['json', 'xml', 'html', 'js', 'dart', 'py', 'c', 'cpp', 'java'].contains(ext)) {
      iconData = Icons.code;
      iconColor = Colors.teal;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Icon(iconData, size: size * 0.6, color: iconColor),
      ),
    );
  }
}
