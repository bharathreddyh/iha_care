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

class _PatientImagesScreenState extends State<PatientImagesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<String> _instanceIds = [];
  List<DicomMeasurement> _measurements = [];
  bool _imagesLoading = true;
  bool _measurementsLoading = true;
  bool _orthancUnreachable = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _imagesLoading = true;
      _measurementsLoading = true;
      _orthancUnreachable = false;
    });
    final service = context.read<OrthancService>();
    final accession = widget.bill.accessionNumber ?? widget.bill.id;

    final reachable = await service.isReachable();
    if (!reachable) {
      if (mounted) {
        setState(() {
          _imagesLoading = false;
          _measurementsLoading = false;
          _orthancUnreachable = true;
        });
      }
      return;
    }

    // Load images and measurements in parallel
    final imagesFuture = service.getInstancesForAccession(accession);
    final measurementsFuture = service.getMeasurements(accession);

    final ids = await imagesFuture;
    if (mounted) setState(() { _instanceIds = ids; _imagesLoading = false; });

    final meas = await measurementsFuture;
    if (mounted) setState(() { _measurements = meas; _measurementsLoading = false; });
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
            onPressed: _loadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              icon: const Icon(Icons.photo_library_outlined),
              text: _imagesLoading ? 'Images' : 'Images (${_instanceIds.length})',
            ),
            Tab(
              icon: const Icon(Icons.biotech_outlined),
              text: _measurementsLoading
                  ? 'Measurements'
                  : 'Measurements (${_measurements.length})',
            ),
          ],
        ),
      ),
      body: _orthancUnreachable
          ? _unreachableView()
          : TabBarView(
              controller: _tabs,
              children: [
                _ImagesTab(
                  instanceIds: _instanceIds,
                  loading: _imagesLoading,
                  patientName: bill.patientName,
                ),
                _MeasurementsTab(
                  measurements: _measurements,
                  loading: _measurementsLoading,
                ),
              ],
            ),
    );
  }

  Widget _unreachableView() => Center(
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
              onPressed: _loadAll,
            ),
          ],
        ),
      );
}

// ── Images tab ────────────────────────────────────────────────────────────────

class _ImagesTab extends StatelessWidget {
  final List<String> instanceIds;
  final bool loading;
  final String patientName;

  const _ImagesTab({
    required this.instanceIds,
    required this.loading,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Checking Orthanc for images…'),
        ]),
      );
    }
    if (instanceIds.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
        ]),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: instanceIds.length,
      itemBuilder: (ctx, i) {
        final id = instanceIds[i];
        final url = context.read<OrthancService>().instancePreviewUrl(id);
        return GestureDetector(
          onTap: () => Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => _FullScreenImageViewer(
                instanceIds: instanceIds,
                initialIndex: i,
                orthancService: context.read<OrthancService>(),
                patientName: patientName,
              ),
            ),
          ),
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
                          child:
                              CircularProgressIndicator(strokeWidth: 2)),
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
    );
  }
}

// ── Measurements tab ──────────────────────────────────────────────────────────

class _MeasurementsTab extends StatelessWidget {
  final List<DicomMeasurement> measurements;
  final bool loading;

  const _MeasurementsTab(
      {required this.measurements, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Fetching measurements…'),
        ]),
      );
    }
    if (measurements.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.biotech_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('No measurement data found.',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Biometry data will appear here once the\nSamsung V6 sends the structured report.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ]),
      );
    }

    // Group by first word of name to create loose categories
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: measurements.length,
      itemBuilder: (_, i) {
        final m = measurements[i];
        return Card(
          child: ListTile(
            dense: true,
            title: Text(
              m.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            trailing: Text(
              m.unit.isNotEmpty
                  ? '${m.displayValue} ${m.unit}'
                  : m.displayValue,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                fontSize: 15,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Full-screen image viewer ──────────────────────────────────────────────────

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
                        child: CircularProgressIndicator(
                            color: Colors.white)),
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
