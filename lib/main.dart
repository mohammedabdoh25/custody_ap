import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MainSystemWindow(onThemeChanged: setThemeMode, currentTheme: _themeMode),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ================= إدارة قاعدة البيانات =================
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
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
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

// ================= النافذة الرئيسية =================
class MainSystemWindow extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final ThemeMode currentTheme;

  const MainSystemWindow({
    Key? key,
    required this.onThemeChanged,
    required this.currentTheme,
  }) : super(key: key);

  @override
  State<MainSystemWindow> createState() => _MainSystemWindowState();
}

class _MainSystemWindowState extends State<MainSystemWindow> with TickerProviderStateMixin {
  TabController? _tabController;
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

    if (!mounted) return;

    final oldController = _tabController;
    setState(() {
      _categories = cats;
      _tabController = TabController(length: 2 + _categories.length, vsync: this);
      _isLoading = false;
    });
    oldController?.dispose();
  }

  void _refresh() {
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _tabController == null) {
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
            ..._categories.map(
              (cat) => Tab(
                icon: const Icon(Icons.folder),
                text: cat['name'].toString(),
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ConstantsTab(onChanged: _refresh),
          SettingsTab(
            onThemeChanged: widget.onThemeChanged,
            currentTheme: widget.currentTheme,
          ),
          ..._categories.map(
            (cat) => CategoryRecordsView(
              key: ValueKey(cat['id']),
              categoryId: cat['id'] as int,
              categoryName: cat['name'].toString(),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= 1. شاشة الثوابت =================
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

    if (!mounted) return;

    setState(() {
      _categories = cats;
      _items = items;
      _entities = ents;
      if (_categories.isNotEmpty) {
        final exists = _categories.any((c) => c['id'] == _selectedCatForItem);
        if (!exists) {
          _selectedCatForItem = _categories.first['id'] as int;
        }
      } else {
        _selectedCatForItem = null;
      }
    });
  }

  @override
  void dispose() {
    _catController.dispose();
    _itemNameController.dispose();
    _entNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        // --- القسم الأول: فئات المخازن ---
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
                          await _loadData();
                          widget.onChanged();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('الفئة موجودة مسبقاً!')),
                          );
                        }
                      },
                      child: const Text('إضافة'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120,
                  child: _categories.isEmpty
                      ? const Center(child: Text('لا توجد فئات مضافة'))
                      : ListView.builder(
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final cat = _categories[index];
                            return ListTile(
                              dense: true,
                              title: Text(cat['name'].toString()),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  final db = await DatabaseManager.instance.database;
                                  await db.delete('categories', where: 'id = ?', whereArgs: [cat['id']]);
                                  await _loadData();
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
        const SizedBox(height: 12),
        // --- القسم الثاني: الأصناف ---
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🛠️ 2. إدارة الأصناف والمواد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (_categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('يرجى إضافة فئة مخزن أولاً لتتمكن من إضافة الأصناف.', style: TextStyle(color: Colors.orange)),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<int>(
                          value: _selectedCatForItem,
                          decoration: const InputDecoration(labelText: 'الفئة'),
                          items: _categories.map((cat) {
                            return DropdownMenuItem<int>(
                              value: cat['id'] as int,
                              child: Text(cat['name'].toString()),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedCatForItem = val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _itemNameController,
                          decoration: const InputDecoration(hintText: 'اسم الصنف...'),
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
                            await _loadData();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('الصنف موجود مسبقاً في هذه الفئة!')),
                            );
                          }
                        },
                        child: const Text('إضافة'),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 140,
                  child: _items.isEmpty
                      ? const Center(child: Text('لا توجد أصناف مضافة'))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return ListTile(
                              dense: true,
                              title: Text(item['name'].toString()),
                              subtitle: Text('الفئة: ${item['cat_name']}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  final db = await DatabaseManager.instance.database;
                                  await db.delete('items', where: 'id = ?', whereArgs: [item['id']]);
                                  await _loadData();
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
        const SizedBox(height: 12),
        // --- القسم الثالث: الجهات والمستلمين ---
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🏢 3. إدارة الجهات والمستلمين', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _entType,
                        decoration: const InputDecoration(labelText: 'النوع'),
                        items: const [
                          DropdownMenuItem(value: 'جهة', child: Text('جهة / قسم')),
                          DropdownMenuItem(value: 'فرد', child: Text('فرد / موظف')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _entType = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _entNameController,
                        decoration: const InputDecoration(hintText: 'اسم الجهة أو المستلم...'),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                          await _loadData();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('الاسم موجود مسبقاً!')),
                          );
                        }
                      },
                      child: const Text('إضافة'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 140,
                  child: _entities.isEmpty
                      ? const Center(child: Text('لا توجد جهات أو مستلمين'))
                      : ListView.builder(
                          itemCount: _entities.length,
                          itemBuilder: (context, index) {
                            final ent = _entities[index];
                            return ListTile(
                              dense: true,
                              title: Text(ent['name'].toString()),
                              subtitle: Text('النوع: ${ent['type']}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  final db = await DatabaseManager.instance.database;
                                  await db.delete('entities', where: 'id = ?', whereArgs: [ent['id']]);
                                  await _loadData();
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

// ================= 2. شاشة الإعدادات =================
class SettingsTab extends StatelessWidget {
  final Function(ThemeMode) onThemeChanged;
  final ThemeMode currentTheme;
  const SettingsTab({
    Key? key,
    required this.onThemeChanged,
    required this.currentTheme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎨 مظهر التطبيق', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                RadioListTile<ThemeMode>(
                  title: const Text('الوضع الليلي (الداكن)'),
                  value: ThemeMode.dark,
                  groupValue: currentTheme,
                  onChanged: (val) {
                    if (val != null) onThemeChanged(val);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('الوضع النهاري (الفاتح)'),
                  value: ThemeMode.light,
                  groupValue: currentTheme,
                  onChanged: (val) {
                    if (val != null) onThemeChanged(val);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ================= 3. شاشة سجلات العهد لكل فئة =================
class CategoryRecordsView extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  const CategoryRecordsView({
    Key? key,
    required this.categoryId,
    required this.categoryName,
  }) : super(key: key);

  @override
  State<CategoryRecordsView> createState() => _CategoryRecordsViewState();
}

class _CategoryRecordsViewState extends State<CategoryRecordsView> {
  List> _records = [];
  List> _items = [];
  List> _entities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategoryData();
  }

  Future<void> _loadCategoryData() async {
    final db = await DatabaseManager.instance.database;
    final records = await db.rawQuery('''
      SELECT r.*, i.name as item_name, e.name as entity_name
      FROM custody_records r
      JOIN items i ON r.item_id = i.id
      JOIN entities e ON r.entity_id = e.id
      WHERE r.category_id = ?
      ORDER BY r.id DESC
    ''', [widget.categoryId]);
    final items = await db.query('items', where: 'category_id = ?', whereArgs: [widget.categoryId]);
    final entities = await db.query('entities');

    if (!mounted) return;

    setState(() {
      _records = records;
      _items = items;
      _entities = entities;
      _isLoading = false;
    });
  }

  void _showAddRecordDialog() {
    if (_items.isEmpty || _entities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إضافة أصناف لهذه الفئة وجهات مستلمة من شاشة الثوابت أولاً!')),
      );
      return;
    }
    int selectedItemId = _items.first['id'] as int;
    int selectedEntityId = _entities.first['id'] as int;
    String selectedStatus = 'مصروفة';
    final qtyController = TextEditingController(text: '1');
    final orderRefController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text('صرف عهدة جديدة (${widget.categoryName})'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        value: selectedItemId,
                        decoration: const InputDecoration(labelText: 'الصنف'),
                        items: _items.map((item) {
                          return DropdownMenuItem<int>(
                            value: item['id'] as int,
                            child: Text(item['name'].toString()),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedItemId = val);
                        },
                      ),
                      DropdownButtonFormField<int>(
                        value: selectedEntityId,
                        decoration: const InputDecoration(labelText: 'الجهة / المستلم'),
                        items: _entities.map((ent) {
                          return DropdownMenuItem<int>(
                            value: ent['id'] as int,
                            child: Text(ent['name'].toString()),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedEntityId = val);
                        },
                      ),
                      TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'الكمية'),
                      ),
                      TextField(
                        controller: orderRefController,
                        decoration: const InputDecoration(labelText: 'رقم أمر الصرف / المرجع'),
                      ),
                      DropdownButtonFormField<String>(
                        value: selectedStatus,
                        decoration: const InputDecoration(labelText: 'حالة العهدة'),
                        items: const [
                          DropdownMenuItem(value: 'مصروفة', child: Text('مصروفة')),
                          DropdownMenuItem(value: 'مسترجعة', child: Text('مسترجعة')),
                          DropdownMenuItem(value: 'تالفة', child: Text('تالفة')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedStatus = val);
                        },
                      ),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(labelText: 'ملاحظات'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final qty = int.tryParse(qtyController.text.trim()) ?? 1;
                      final db = await DatabaseManager.instance.database;
                      await db.insert('custody_records', {
                        'category_id': widget.categoryId,
                        'entity_id': selectedEntityId,
                        'item_id': selectedItemId,
                        'quantity': qty,
                        'order_ref': orderRefController.text.trim(),
                        'status': selectedStatus,
                        'issue_date': DateTime.now().toString().split(' ')[0],
                        'notes': notesController.text.trim(),
                      });
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _loadCategoryData();
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      qtyController.dispose();
      orderRefController.dispose();
      notesController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      body: _records.isEmpty
          ? Center(child: Text('لا توجد سجلات عهد في قسم (${widget.categoryName})'))
          : ListView.builder(
              padding: const EdgeInsets.all(12.0),
              itemCount: _records.length,
              itemBuilder: (context, index) {
                final rec = _records[index];
                return Card(
                  child: ListTile(
                    title: Text('${rec['item_name']} (الكمية: ${rec['quantity']})'),
                    subtitle: Text(
                      'المستلم: ${rec['entity_name']} | الحالة: ${rec['status']}\nالتاريخ: ${rec['issue_date'] ?? '-'} | المرجع: ${rec['order_ref'] ?? '-'}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        final db = await DatabaseManager.instance.database;
                        await db.delete('custody_records', where: 'id = ?', whereArgs: [rec['id']]);
                        _loadCategoryData();
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRecordDialog,
        icon: const Icon(Icons.add),
        label: const Text('صرف عهدة'),
      ),
    );
  }
}
