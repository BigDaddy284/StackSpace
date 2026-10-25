import 'package:flutter/material.dart';
import 'package:stack_space/plugins/document/virtualized_editor/virtualized_renderer.dart';
import 'package:stack_space/plugins/document/virtualized_editor/virtualized_editor_widget.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Virtualized Document Editor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const VirtualizedDocumentDemo(),
    );
  }
}

class VirtualizedDocumentDemo extends StatefulWidget {
  const VirtualizedDocumentDemo({Key? key}) : super(key: key);

  @override
  State<VirtualizedDocumentDemo> createState() => _VirtualizedDocumentDemoState();
}

class _VirtualizedDocumentDemoState extends State<VirtualizedDocumentDemo> {
  late VirtualizedRenderer _renderer;
  final TextEditingController _controller = TextEditingController();
  int _documentSize = 1000;

  @override
  void initState() {
    super.initState();
    _renderer = VirtualizedRenderer(totalLines: _documentSize, chunkSize: 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Virtualized Document Editor'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'Document size (lines)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        if (value.isNotEmpty) {
                          _documentSize = int.tryParse(value) ?? 1000;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _renderer = VirtualizedRenderer(totalLines: _documentSize, chunkSize: 100);
                    });
                  },
                  child: const Text('Update'),
                ),
              ],
            ),
          ),
          Expanded(
            child: VirtualizedEditorWidget(
              document: _renderer,
              textStyle: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}