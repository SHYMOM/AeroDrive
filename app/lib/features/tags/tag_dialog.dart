import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/features/tags/tag_service.dart';

extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  Color get contrastColor {
    // WCAG luminance formula approximation
    final luminance = computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}

class TagDialog extends ConsumerStatefulWidget {
  final FileData file;
  
  const TagDialog({super.key, required this.file});

  static void show(BuildContext context, FileData file) {
    showDialog(
      context: context,
      builder: (context) => TagDialog(file: file),
    );
  }

  @override
  ConsumerState<TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends ConsumerState<TagDialog> {
  final _tagController = TextEditingController();
  String? _selectedColor = TagService.curatedColors.first;
  List<Tag> _fileTags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await ref.read(tagServiceProvider).getTagsForFile(widget.file.id);
    if (mounted) {
      setState(() {
        _fileTags = tags;
        _isLoading = false;
      });
    }
  }

  Future<void> _addTag() async {
    final name = _tagController.text.trim();
    if (name.isEmpty) return;

    final service = ref.read(tagServiceProvider);
    final newTag = await service.getOrCreateTag(name, hexColor: _selectedColor);
    await service.attachTagToFile(widget.file.id, newTag.id);
    
    _tagController.clear();
    await _loadTags();
  }

  Future<void> _removeTag(String tagId) async {
    final service = ref.read(tagServiceProvider);
    await service.removeTagFromFile(widget.file.id, tagId);
    await _loadTags();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Tags'),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_fileTags.isEmpty)
              const Text('No tags assigned to this file.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _fileTags.map((tag) {
                  final color = tag.color != null ? HexColor.fromHex(tag.color!) : Colors.grey;
                  return Chip(
                    backgroundColor: color,
                    label: Text(
                      tag.name,
                      style: TextStyle(color: color.contrastColor, fontSize: 12),
                    ),
                    onDeleted: () => _removeTag(tag.id),
                    deleteIconColor: color.contrastColor,
                  );
                }).toList(),
              ),
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            
            TextField(
              controller: _tagController,
              decoration: InputDecoration(
                labelText: 'New Tag',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addTag,
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _addTag(),
            ),
            const SizedBox(height: 16),
            const Text('Pick a color:'),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: TagService.curatedColors.length,
              itemBuilder: (context, index) {
                final hex = TagService.curatedColors[index];
                final color = HexColor.fromHex(hex);
                final isSelected = _selectedColor == hex;

                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedColor = hex);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                      boxShadow: isSelected
                          ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
                          : null,
                    ),
                    child: isSelected
                        ? Icon(Icons.check, color: color.contrastColor, size: 16)
                        : null,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
