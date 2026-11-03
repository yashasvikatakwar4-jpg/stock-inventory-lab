import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

const categories = ['Electronics', 'Stationery', 'Hardware', 'Grocery'];
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? failure;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Only use anonymous access if enabled by your lecturer. Rules remain enforced.
    if (const bool.fromEnvironment('ANONYMOUS_AUTH', defaultValue: true)) {
      try { await FirebaseAuth.instance.signInAnonymously(); }
      on FirebaseAuthException catch (e) {
        if (!['operation-not-allowed','admin-restricted-operation','configuration-not-found'].contains(e.code)) rethrow;
      }
    }
  } catch (e) { failure = e.toString(); }
  runApp(MaterialApp(debugShowCheckedModeBanner: false, title: 'Stockroom',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff28533f),
      scaffoldBackgroundColor: const Color(0xfff4f5ef),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder())),
    home: failure == null ? const InventoryPage() : Scaffold(body: Center(child: Padding(
      padding: const EdgeInsets.all(30), child: SelectableText('Firebase initialization failed.\n$failure\nFollow README setup and run flutterfire configure.'))))));
}
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override State<InventoryPage> createState() => _InventoryPageState();
}
class _InventoryPageState extends State<InventoryPage> {
  final formKey = GlobalKey<FormState>();
  final sku = TextEditingController(), name = TextEditingController();
  final qty = TextEditingController(), price = TextEditingController(), reorder = TextEditingController();
  final search = TextEditingController();
  String? category;
  String filterCategory = 'All';
  bool lowOnly = false, ascending = true, saving = false;
  late Stream<QuerySnapshot<Map<String, dynamic>>> records;
  CollectionReference<Map<String, dynamic>> get collection => FirebaseFirestore.instance.collection('stockItems');
  @override void initState() { super.initState(); records = collection.snapshots(); }
  @override void dispose() { for (final c in [sku,name,qty,price,reorder,search]) { c.dispose(); } super.dispose(); }
  void message(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }
  String? whole(String? s) {
    final t = (s ?? '').trim(); final n = int.tryParse(t);
    return !RegExp(r'^\d+$').hasMatch(t) || n == null || n < 0 ? 'Enter a whole number of 0 or above' : null;
  }
  Future<void> save() async {
    if (saving || !formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await collection.add({'sku': sku.text.trim(), 'itemName': name.text.trim(), 'category': category,
        'quantity': int.parse(qty.text.trim()), 'unitPrice': double.parse(price.text.trim()),
        'reorderLevel': int.parse(reorder.text.trim()), 'createdAt': FieldValue.serverTimestamp()});
      if (!mounted) return;
      for (final c in [sku,name,qty,price,reorder]) { c.clear(); }
      formKey.currentState!.reset();
      setState(() => category = null);
      message('Item saved to Firestore');
    } catch (e) { message('Save failed. Your inputs were kept. $e'); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Widget field(String label, TextEditingController c, String? Function(String?) validator, {bool numeric = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 16), child: TextFormField(controller: c, validator: validator,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label)));
  Widget entryForm() => Card(child: Padding(padding: const EdgeInsets.all(24), child: Form(key: formKey, child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Add a stock item', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 20),
    field('SKU · STK-101', sku, (v) => RegExp(r'^STK-\d{3}$').hasMatch((v ?? '').trim()) ? null : 'Use STK- followed by exactly 3 digits'),
    field('Item name', name, (v) => (v ?? '').trim().length >= 3 ? null : 'Enter at least 3 characters'),
    DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Category'),
      items: categories.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      validator: (v) => categories.contains(v) ? null : 'Choose a category', onChanged: (v) => setState(() => category = v)),
    const SizedBox(height: 16), field('Quantity', qty, whole, numeric: true),
    field('Unit price · RM', price, (v) { final t = (v ?? '').trim(); final n = double.tryParse(t);
      return !RegExp(r'^\d+(\.\d+)?$').hasMatch(t) || n == null || !n.isFinite || n <= 0 ? 'Enter a price greater than 0' : null; }, numeric: true),
    field('Reorder level', reorder, whole, numeric: true),
    FilledButton(onPressed: saving ? null : save, child: Padding(padding: const EdgeInsets.all(14), child: Text(saving ? 'Saving…' : 'Save item'))),
  ]))));
  Widget inventory() => Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Your inventory', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 20),
    TextField(controller: search, decoration: const InputDecoration(labelText: 'Search name or SKU', prefixIcon: Icon(Icons.search)), onChanged: (_) => setState(() {})),
    const SizedBox(height: 16), Wrap(spacing: 14, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(width: 180, child: DropdownButtonFormField<String>(value: filterCategory, decoration: const InputDecoration(labelText: 'Category'),
        items: ['All', ...categories].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => filterCategory = v ?? 'All'))),
      FilterChip(label: const Text('Low-stock only'), selected: lowOnly, onSelected: (v) => setState(() => lowOnly = v)),
      DropdownButton<bool>(value: ascending, items: const [DropdownMenuItem(value: true, child: Text('Quantity ↑')), DropdownMenuItem(value: false, child: Text('Quantity ↓'))], onChanged: (v) => setState(() => ascending = v ?? true)),
      TextButton(onPressed: () => setState(() { search.clear(); filterCategory = 'All'; lowOnly = false; ascending = true; }), child: const Text('Clear filters')),
    ]), const SizedBox(height: 20),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: records, builder: (context, snapshot) {
      if (snapshot.hasError) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Could not load Firestore records: ${snapshot.error}'), TextButton(onPressed: () => setState(() => records = collection.snapshots()), child: const Text('Retry'))]);
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final query = search.text.trim().toLowerCase();
      final all = snapshot.data!.docs.map((doc) => doc.data()).toList();
      bool valid(Map<String,dynamic> x) => x['sku'] is String && x['itemName'] is String && categories.contains(x['category']) && x['quantity'] is int && x['quantity'] >= 0 && x['reorderLevel'] is int && x['reorderLevel'] >= 0 && x['unitPrice'] is num && (x['unitPrice'] as num).isFinite && x['unitPrice'] > 0;
      final compatible = all.where(valid).toList();
      final visible = compatible.where((x) => (x['itemName'].toString().toLowerCase().contains(query) || x['sku'].toString().toLowerCase().contains(query)) && (filterCategory == 'All' || x['category'] == filterCategory) && (!lowOnly || x['quantity'] <= x['reorderLevel'])).toList();
      visible.sort((a,b) => ascending ? (a['quantity'] as int).compareTo(b['quantity'] as int) : (b['quantity'] as int).compareTo(a['quantity'] as int));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${visible.length} of ${compatible.length} items · ${snapshot.data!.metadata.isFromCache ? 'Cached Firestore data' : 'Live Firestore data'}'),
        if (compatible.length != all.length) const Text('Some incompatible records were skipped.'),
        if (visible.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Text(all.isEmpty ? 'No saved items. Add your first stock item.' : 'No matching items. Try clearing filters.'))
        else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('SKU')),DataColumn(label: Text('Name')),DataColumn(label: Text('Category')),DataColumn(label: Text('Qty')),DataColumn(label: Text('Price RM')),DataColumn(label: Text('Reorder'))], rows: visible.map((x) => DataRow(cells: [DataCell(Text(x['sku'])),DataCell(Text(x['itemName'])),DataCell(Text(x['category'])),DataCell(Text('${x['quantity']}', style: TextStyle(color: x['quantity'] <= x['reorderLevel'] ? Colors.deepOrange : null))),DataCell(Text((x['unitPrice'] as num).toStringAsFixed(2))),DataCell(Text('${x['reorderLevel']}'))])).toList())),
      ]);
    }),
  ])));
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Stockroom · Inventory Manager')), body: LayoutBuilder(builder: (context, box) => SingleChildScrollView(padding: const EdgeInsets.all(20), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1250), child: box.maxWidth > 950 ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 350, child: entryForm()), const SizedBox(width: 20), Expanded(child: inventory())]) : Column(children: [entryForm(), const SizedBox(height: 20), inventory()]))))));
}
