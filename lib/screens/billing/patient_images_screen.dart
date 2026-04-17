import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/billing/bill.dart';
import '../../services/orthanc_service.dart';
import '../../utils/date_formatter.dart';

class PatientImagesScreen extends StatefulWidget {
  final Bill bill;

  const PatientImagesScreen({super.key, required this.bill});

  @override
  State<PatientImagesScreen> createState() => _PatientImagesScreenState();
}

class _PatientImagesScreenState extends State<PatientImagesScreen> {
  List<String> _instanceIds = [];
  bool _loading = true;
  bool _orthancUnreachable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _orthancUnreachable = false; });
    final service = context.read<OrthancService>();

    final reachable = await service.isReachable();
    if (!reachable) {
      if (mounted) setState(() { _loading = false; _orthancUnreachable = true; });
      return;
    }

    final ids = await service.getInstancesForAccession(
        widget.bill.accessionNumber ?? widget.bill.id);
    if (mounted) setState(() { _instanceIds = ids; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(bill.patientName),
            Text(
              '${bill.id} · ${formatDate(bill.createdAt)}',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Checking Orthanc for images…'),
          ],
        ),
      );
    }

    if (_orthancUnreachable) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Orthanc is not reachable.',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Make sure Orthanc is running on this PC.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: _load,
            ),
          ],
        ),
      );
    }

    if (_instanceIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported_outlined,
                size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No images received yet.',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Images will appear here once the scan is\ncompleted on the Samsung V6.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              onPressed: _load,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '${_instanceIds.length} image${_instanceIds.length == 1 ? '' : 's'}',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _instanceIds.length,
            itemBuilder: (ctx, i) {
              final id = _instanceIds[i];
              final url =
                  context.read<OrthancService>().instancePreviewUrl(id);
              return GestureDetector(
                onTap: () => _openFullScreen(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                          ),
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: Colors.grey)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openFullScreen(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(
          instanceIds: _instanceIds,
          initialIndex: initialIndex,
          orthancService: context.read<OrthancService>(),
          patientName: widget.bill.patientName,
        ),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatefulWidget {
  final List<String> instanceIds;
  final int initialIndex;
  final OrthancService orthancService;
  final String patientName;

  const _FullScreenImageViewer({
    required this.instanceIds,
    required this.initialIndex,
    required this.orthancService,
    required this.patientName,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.patientName}  ·  ${_current + 1} / ${widget.instanceIds.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.instanceIds.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) {
          final url = widget.orthancService
              .instancePreviewUrl(widget.instanceIds[i]);
          return InteractiveViewer(
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 64),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
