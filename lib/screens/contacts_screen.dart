import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_localizations.dart';
import '../models/contact.dart';
import '../repositories/contacts_repository.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _repo = ContactsRepository();
  List<Contact> _contacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final contacts = await _repo.getAll();
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load contacts.')),
        );
      }
    }
  }

  Future<void> _addContact() async {
    final result = await showDialog<Contact>(
      context: context,
      builder: (_) => const _ContactDialog(),
    );
    if (result != null) {
      await _repo.add(result);
      await _load();
    }
  }

  Future<void> _editContact(Contact contact) async {
    final result = await showDialog<Contact>(
      context: context,
      builder: (_) => _ContactDialog(existing: contact),
    );
    if (result != null) {
      await _repo.update(result);
      await _load();
    }
  }

  Future<void> _deleteContact(Contact contact) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.contactsScreenTitle),
        content: Text(l10n.contactsRemoveTitle(contact.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.remove, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repo.remove(contact.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.contactsScreenTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: _addContact,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? _EmptyState(l10n: l10n, onAdd: _addContact)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _contacts.length,
                  itemBuilder: (_, i) => _ContactTile(
                    contact: _contacts[i],
                    onEdit: () => _editContact(_contacts[i]),
                    onDelete: () => _deleteContact(_contacts[i]),
                  ),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppLocalizations l10n;
  final VoidCallback onAdd;
  const _EmptyState({required this.l10n, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 72,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.contactsEmpty,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.contactsEmptyHint,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(l10n.addContact),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final Contact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactTile({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Text(
            contact.name[0].toUpperCase(),
            style: TextStyle(color: cs.onPrimaryContainer),
          ),
        ),
        title: Text(contact.name),
        subtitle: Text(
          contact.phone,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit, color: cs.onSurfaceVariant),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactDialog extends StatefulWidget {
  final Contact? existing;
  const _ContactDialog({this.existing});

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _phone = TextEditingController(text: widget.existing?.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? l10n.editContact : l10n.addContact),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.contactNameLabel,
                prefixIcon: const Icon(Icons.person),
              ),
              inputFormatters: [LengthLimitingTextInputFormatter(50)],
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l10n.required_ : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: InputDecoration(
                labelText: l10n.contactPhoneLabel,
                prefixIcon: const Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.required_;
                final phoneRegex = RegExp(r'^\+?[0-9\s\-().]{7,20}$');
                if (!phoneRegex.hasMatch(v.trim())) return l10n.required_;
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final contact = Contact(
                id: widget.existing?.id ?? const Uuid().v4(),
                name: _name.text.trim(),
                phone: _phone.text.trim(),
              );
              Navigator.pop(context, contact);
            }
          },
          child: Text(isEditing ? l10n.save : l10n.addContact),
        ),
      ],
    );
  }
}
