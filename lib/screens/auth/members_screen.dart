import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';

/// Lists everyone in the current centre, and shows the centre code to share
/// with staff so they can join.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  bool _loading = true;
  String? _error;
  List<CentreMemberInfo> _members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await context.read<AuthService>().listCentreMembers();
      if (mounted) {
        setState(() {
          _members = members;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load members. Pull down to retry.';
          _loading = false;
        });
      }
    }
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Centre code "$code" copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final code = auth.centreCode;
    final myEmail = auth.currentUserEmail;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Centre code share card ────────────────────────────────────
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.centreName ?? 'Your centre',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Share this code so staff can join:',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            code ?? '—',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (code != null)
                      IconButton.filledTonal(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copy code',
                        onPressed: () => _copyCode(code),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'People (${_members.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              )
            else if (_members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('No members found.')),
              )
            else
              ..._members.map((m) => _memberTile(m, m.email == myEmail)),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(CentreMemberInfo m, bool isMe) {
    final isOwner = m.role == 'owner';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            m.email.isNotEmpty ? m.email[0].toUpperCase() : '?',
          ),
        ),
        title: Text(m.email),
        subtitle: isMe ? const Text('You') : null,
        trailing: Chip(
          label: Text(
            isOwner ? 'Owner' : 'Staff',
            style: const TextStyle(fontSize: 11),
          ),
          backgroundColor: isOwner
              ? Theme.of(context).colorScheme.tertiaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
