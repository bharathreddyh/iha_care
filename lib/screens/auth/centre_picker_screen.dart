import 'package:flutter/material.dart';

import '../../models/auth/app_centre.dart';

class CentrePickerScreen extends StatelessWidget {
  final List<AppCentre> centres;

  const CentrePickerScreen({super.key, required this.centres});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Centre')),
      body: Center(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Choose a centre to work with:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...centres.map((c) => Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(c.name[0].toUpperCase()),
                      ),
                      title: Text(c.name),
                      subtitle: Text(c.code),
                      trailing: c.role == 'owner'
                          ? const Chip(label: Text('Owner'))
                          : null,
                      onTap: () => Navigator.pop(context, c),
                    ),
                  )),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
