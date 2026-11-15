import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() {
  runApp(const CustodyApp());
}

class CustodyApp extends StatefulWidget {
  const CustodyApp({Key? key}) : super(key: key);

  @override
  State<CustodyApp> createState() => _CustodyAppState();
}

class _CustodyAppState extends State<CustodyApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'النظام الشامل لإدارة وصرف وتتبع العهد والمخازن',
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Amiri',
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        cardColor: Colors.white,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Amiri',
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF090D16),
        cardColor: const Color(0xFF0F172A),
      ),
      home: MainSystemWindow(onThemeChanged: setThemeMode),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DatabaseManager {
  static final DatabaseManager instance = DatabaseManager._init();
  static Database? _database;

  DatabaseManager._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('custody_system_v3.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        UNIQUE(name, category_id),
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE entities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        type TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE custody_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        entity_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        order_ref TEXT,
        status TEXT NOT NULL,
        issue_date TEXT,
        notes TEXT,
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE CASCADE,
        FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE,
        FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE
      )
    ''');
  }
}

class MainSystemWindow extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  const MainSystemWindow({Key? key, required this.onThemeChanged}) : super(key: key);

  @override
  State<MainSystemWindow> createState() => _MainSystemWindowState();
}

class _MainSystemWindowState extends State<MainSystemWindow> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final db = await DatabaseManager.instance.database;
    final cats = await db.query('categories');
    setState(() {
      _categories = cats;
      // 2 tabs for Constants and Settings, plus categories count
      _tabController = TabController(length: 2 + _categories.length, vsync: this);
      _isLoading = false;
    });
  }

  void _refresh() {
    _loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🛡️ النظام الشامل لإدارة وتتبع العهد والمخازن'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            const Tab(icon: Icon(Icons.settings_applications), text: 'شاشة الثوابت'),
            const Tab(icon: Icon(Icons.palette), text: 'شاشة الإعدادات'),
            ..._categories.map((cat) => Tab(icon: const Icon(Icons.folder), text: cat['name'].toString())).toList(),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ConstantsTab(onChanged: _refresh),
          SettingsTab(onThemeChanged: widget.onThemeChanged),
          ..._categories.map((cat) => CategoryRecordsView(categoryId: cat['id'], categoryName: cat['name'])).toList(),
        ],
      ),
    );
  }
}

// ----------------- شاشة الثوابت -----------------
class ConstantsTab extends StatefulWidget {
  final VoidCallback onChanged;
  const ConstantsTab({Key? key, required this.onChanged}) : super(key: key);

  @override
  State<ConstantsTab> createState() => _ConstantsTabState();
}

class _ConstantsTabState extends State<ConstantsTab> {
  final TextEditingController _catController = TextEditingController();
  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _entNameController = TextEditingController();

  int? _selectedCatForItem;
  String _entType = 'جهة';

  List> _categories = [];
  List> _items = [];
  List> _entities = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = await DatabaseManager.instance.database;
    final cats = await db.query('categories');
    final items = await db.rawQuery('''
      SELECT i.id, i.name, c.name as cat_name 
      FROM items i JOIN categories c ON i.category_id = c.id
    ''');
    final ents = await db.query('entities');

    setState(() {
      _categories = cats;
      _items = items;
      _entities = ents;
      if (_categories.isNotEmpty && _selectedCatForItem == null) {
        _selectedCatForItem = _categories.first['id'] as int;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        // 1. الفئات
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📦 1. إدارة فئات المخازن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _catController,
                        decoration: const InputDecoration(hintText: 'اسم الفئة الجديدة...'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        if (_catController.text.trim().isEmpty) return;
                        try {
                          final db = await DatabaseManager.instance.database;
                          await db.insert('categories', {'name': _catController.text.trim()});
                          _catController.clear();
                          _loadData();
                          widget.onChanged();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الفئة موجودة مسبقاً!')));
                        }
                      },
                      child: const Text('إضافة'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      return ListTile(
                        title: Text('${cat['id']} - ${cat['name']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final db = await DatabaseManager.instance.database;
                            await db.delete('categories', where: 'id = ?', whereArgs: [cat['id']]);
                            _loadData();
                            widget.onChanged();
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. الأصناف
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📌 2. إدارة الأصناف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                DropdownButtonFormField<int>(
                  value: _selectedCatForItem,
                  items: _categories.map((c) => DropdownMenuItem<int>(
                    value: c['id'] as int,
                    child: Text(c['name'].toString()),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedCatForItem = val),
                  decoration: const InputDecoration(labelText: 'اختر الفئة التابع لها الصنف'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _itemNameController,
                        decoration: const InputDecoration(hintText: 'اسم الصنف الجديد...'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        if (_itemNameController.text.trim().isEmpty || _selectedCatForItem == null) return;
                        try {
                          final db = await DatabaseManager.instance.database;
                          await db.insert('items', {
                            'name': _itemNameController.text.trim(),
                            'category_id': _selectedCatForItem,
                          });
                          _itemNameController.clear();
                          _loadData();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الصنف موجود مسبقاً في هذه الفئة!')));
                        }
                      },
                      child: const Text('إضافة صنف'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile(
                        title: Text('${item['name']} (فئة: ${item['cat_name']})'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final db = await DatabaseManager.instance.database;
                            await db.delete('items', where: 'id = ?', whereArgs: [item['id']]);
                            _loadData();
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // 3. الجهات والأفراد
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🏢 3. إدارة الجهات والأفراد المستفيدين', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _entNameController,
                        decoration: const InputDecoration(hintText: 'اسم الجهة أو الفرد...'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _entType,
                        items: ['جهة', 'فرد'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (val) => setState(() => _entType = val!),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (_entNameController.text.trim().isEmpty) return;
                        try {
                          final db = await DatabaseManager.instance.database;
                          await db.insert('entities', {
                            'name': _entNameController.text.trim(),
                            'type': _entType,
                          });
                          _entNameController.clear();
                          _loadData();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الجهة أو الفرد مسجل مسبقاً!')));
                        }
                      },
                      child: const Text('إضافة'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    itemCount: _entities.length,
                    itemBuilder: (context, index) {
                      final ent = _entities[index];
                      return ListTile(
                        title: Text('${ent['name']} (${ent['type']})'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final db = await DatabaseManager.instance.database;
                            await db.delete('entities', where: 'id = ?', whereArgs: [ent['id']]);
                            _loadData();
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ----------------- شاشة الإعدادات والستايلات -----------------
class SettingsTab extends StatelessWidget {
  final Function(ThemeMode) onThemeChanged;
  const SettingsTab({Key? key, required this.onThemeChanged}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🎨 تخصيص مظهر وثيمات النظام', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          ListTile(
            title: const Text('الوضع الداكن الاحترافي'),
            leading: const Icon(Icons.dark_mode),
            onTap: () => onThemeChanged(ThemeMode.dark),
          ),
          ListTile(
            title: const Text('الوضع الفاتح العصري'),
            leading: const Icon(Icons.light_mode),
            onTap: () => onThemeChanged(ThemeMode.light),
          ),
        ],
      ),
    );
  }
}

// ----------------- سجلات العهد لكل فئة (جدول تفصيلي) -----------------
class CategoryRecordsView extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  const CategoryRecordsView({Key? key, required this.categoryId, required this.categoryName}) : super(key: key);

  @override
  State<CategoryRecordsView> createState() => _CategoryRecordsViewState();
}

class _CategoryRecordsViewState extends State<CategoryRecordsView> {
  List> _records = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final db = await DatabaseManager.instance.database;
    final res = await db.rawQuery('''
      SELECT c.*, e.name as entity_name, i.name as item_name
      FROM custody_records c
      JOIN entities e ON c.entity_id = e.id
      JOIN items i ON c.item_id = i.id
      WHERE c.category_id = ?
    ''', [widget.categoryId]);
    setState(() {
      _records = res;
    });
  }

  void _openDialog({Map<String, dynamic>? record}) {
    showDialog(
      context: context,
      builder: (context) => CustodyDialog(categoryId: widget.categoryId, record: record, onSave: _loadRecords),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('📂 سجلات فئة: ${widget.categoryName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ElevatedButton.icon(
                onPressed: () => _openDialog(),
                icon: const Icon(Icons.add),
                label: const Text('إضافة حركة صرف'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _records.isEmpty
                ? const Center(child: Text('لا توجد سجلات عهدة مضافة لهذه الفئة بعد.'))
                : ListView.builder(
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                      final rec = _records[index];
                      return Card(
                        child: ListTile(
                          title: Text('المستفيد: ${rec['entity_name']} | الصنف: ${rec['item_name']}'),
                          subtitle: Text('الكمية: ${rec['quantity']} | الحالة: ${rec['status']}\nأمر الصرف: ${rec['order_ref']} | التاريخ: ${rec['issue_date']}'),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _openDialog(record: rec),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  final db = await DatabaseManager.instance.database;
                                  await db.delete('custody_records', where: 'id = ?', whereArgs: [rec['id']]);
                                  _loadRecords();
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ----------------- نافذة إضافة / تعديل حركة عهدة -----------------
class CustodyDialog extends StatefulWidget {
  final int categoryId;
  final Map<String, dynamic>? record;
  final VoidCallback onSave;

  const CustodyDialog({Key? key, required this.categoryId, this.record, required this.onSave}) : super(key: key);

  @override
  State<CustodyDialog> createState() => _CustodyDialogState();
}

class _CustodyDialogState extends State<CustodyDialog> {
  List> _entities = [];
  List> _items = [];

  int? _selectedEntity;
  int? _selectedItem;
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _orderController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  String _status = 'معلقة (بانتظار التحقق)';
  String _date = DateTime.now().toString().split(' ')[0];

  @override
  void initState() {
    super.initState();
    _qtyController.text = widget.record?['quantity']?.toString() ?? '1';
    _orderController.text = widget.record?['order_ref']?.toString() ?? '';
    _notesController.text = widget.record?['notes']?.toString() ?? '';
    if (widget.record != null) {
      _status = widget.record!['status'];
      _date = widget.record!['issue_date'] ?? _date;
    }
    _loadDropdowns();
  }

  Future<void> _loadDropdowns() async {
    final db = await DatabaseManager.instance.database;
    final ents = await db.query('entities');
    final items = await db.query('items', where: 'category_id = ?', whereArgs: [widget.categoryId]);

    setState(() {
      _entities = ents;
      _items = items;

      if (_entities.isNotEmpty) {
        _selectedEntity = widget.record?['entity_id'] ?? _entities.first['id'];
      }
      if (_items.isNotEmpty) {
        _selectedItem = widget.record?['item_id'] ?? _items.first['id'];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.record == null ? 'إضافة حركة عهدة جديدة' : 'تعديل حركة العهدة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: _selectedEntity,
              items: _entities.map((e) => DropdownMenuItem<int>(
                value: e['id'] as int,
                child: Text('${e['name']} (${e['type']})'),
              )).toList(),
              onChanged: (val) => setState(() => _selectedEntity = val),
              decoration: const InputDecoration(labelText: 'الجهة / المستفيد'),
            ),
            DropdownButtonFormField<int>(
              value: _selectedItem,
              items: _items.map((i) => DropdownMenuItem<int>(
                value: i['id'] as int,
                child: Text(i['name'].toString()),
              )).toList(),
              onChanged: (val) => setState(() => _selectedItem = val),
              decoration: const InputDecoration(labelText: 'الصنف'),
            ),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الكمية'),
            ),
            TextField(
              controller: _orderController,
              decoration: const InputDecoration(labelText: 'أمر الصرف'),
            ),
            DropdownButtonFormField<String>(
              value: _status,
              items: [
                'معلقة (بانتظار التحقق)',
                'تم التحقق والاستلام',
                'تالف أو مفقود (مخصوم)'
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) => setState(() => _status = val!),
              decoration: const InputDecoration(labelText: 'الحالة الميدانية'),
            ),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'ملاحظات / أسباب التلف'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_selectedEntity == null || _selectedItem == null) return;
            final db = await DatabaseManager.instance.database;
            final data = {
              'category_id': widget.categoryId,
              'entity_id': _selectedEntity,
              'item_id': _selectedItem,
              'quantity': int.tryParse(_qtyController.text) ?? 1,
              'order_ref': _orderController.text.trim(),
              'status': _status,
              'issue_date': _date,
              'notes': _notesController.text.trim(),
            };

            if (widget.record == null) {
              await db.insert('custody_records', data);
            } else {
              await db.update('custody_records', data, where: 'id = ?', whereArgs: [widget.record!['id']]);
            }

            widget.onSave();
            Navigator.pop(context);
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}