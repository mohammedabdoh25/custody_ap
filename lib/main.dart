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
    _database = await _initDB('custody_system_v4.db');
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
        name TEXT UNIQUE NOT NULL,
        custom_columns TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        total_inbound INTEGER NOT NULL DEFAULT 0,
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
        extra_data TEXT DEFAULT '{}',
        notes TEXT,
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE CASCADE,
        FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE,
        FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE losses_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        custody_record_id INTEGER,
        item_id INTEGER NOT NULL,
        entity_id INTEGER,
        quantity INTEGER NOT NULL,
        status TEXT NOT NULL,
        loss_reason TEXT,
        loss_date TEXT,
        notes TEXT,
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE CASCADE,
        FOREIGN KEY (custody_record_id) REFERENCES custody_records (id) ON DELETE SET NULL,
        FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE,
        FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE SET NULL
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
    final List> cats = (await db.query('categories'))
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    if (!mounted) return;

    final oldController = _tabController;
    setState(() {
      _categories = cats;
      // الترتيب: 1. الثوابت، 2. المؤشرات وجرد الجهات، 3. الإعدادات، ثم فئات المخازن المضافة
      _tabController = TabController(length: 3 + _categories.length, vsync: this);
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
            const Tab(icon: Icon(Icons.analytics), text: 'المؤشرات وجرد الجهات'),
            const Tab(icon: Icon(Icons.palette), text: 'شاشة الإعدادات'),
            ..._categories.map(
              (cat) => Tab(
                icon: const Icon(Icons.folder),
                text: '📁 ${cat['name']}',
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ConstantsTab(onChanged: _refresh),
          DashboardTab(key: UniqueKey()),
          SettingsTab(
            onThemeChanged: widget.onThemeChanged,
            currentTheme: widget.currentTheme,
          ),
          ..._categories.map(
            (cat) => CategoryRecordsView(
              key: ValueKey(cat['id']),
              categoryId: cat['id'] as int,
              categoryName: cat['name'].toString(),
              customColumns: cat['custom_columns']?.toString() ?? '',
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
  final TextEditingController _catColsController = TextEditingController();
  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _itemInboundController = TextEditingController(text: '10');
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
    final List> cats = (await db.query('categories'))
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final List> items = (await db.rawQuery('''
      SELECT i.id, i.name, i.total_inbound, c.name as cat_name
      FROM items i JOIN categories c ON i.category_id = c.id
    '''))
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final List> ents = (await db.query('entities'))
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

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
    _catColsController.dispose();
    _itemNameController.dispose();
    _itemInboundController.dispose();
    _entNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        // --- القسم الأول: فئات المخازن والأعمدة المخصصة ---
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📦 1. إدارة فئات المخازن والأعمدة المخصصة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextField(
                  controller: _catController,
                  decoration: const InputDecoration(labelText: 'اسم الفئة (مثال: آليات، اتصالات...)'),
                ),
                TextField(
                  controller: _catColsController,
                  decoration: const InputDecoration(labelText: 'الأعمدة المخصصة مفصولين بفاصلة (رقم الهيكل, المالك)'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (_catController.text.trim().isEmpty) return;
                    try {
                      final db = await DatabaseManager.instance.database;
                      await db.insert('categories', {
                        'name': _catController.text.trim(),
                        'custom_columns': _catColsController.text.trim(),
                      });
                      _catController.clear();
                      _catColsController.clear();
                      await _loadData();
                      widget.onChanged();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('الفئة موجودة مسبقاً!')),
                      );
                    }
                  },
                  child: const Text('إضافة الفئة'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 100,
                  child: _categories.isEmpty
                      ? const Center(child: Text('لا توجد فئات مضافة'))
                      : ListView.builder(
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final cat = _categories[index];
                            return ListTile(
                              dense: true,
                              title: Text(cat['name'].toString()),
                              subtitle: Text('الأعمدة: ${cat['custom_columns'] ?? ''}'),
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
        // --- القسم الثاني: الأصناف والوارد ---
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🛠️ 2. إدارة الأصناف وإجمالي الوارد للمخزن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (_categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('يرجى إضافة فئة مخزن أولاً لتتمكن من إضافة الأصناف.', style: TextStyle(color: Colors.orange)),
                  )
                else
                  Column(
                    children: [
                      DropdownButtonFormField<int>(
                        value: _selectedCatForItem,
                        decoration: const InputDecoration(labelText: 'اختر الفئة'),
                        items: _categories.map((cat) {
                          return DropdownMenuItem<int>(
                            value: cat['id'] as int,
                            child: Text(cat['name'].toString()),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedCatForItem = val),
                      ),
                      TextField(
                        controller: _itemNameController,
                        decoration: const InputDecoration(labelText: 'اسم الصنف الجديد...'),
                      ),
                      TextField(
                        controller: _itemInboundController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'إجمالي الوارد للمخزن'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () async {
                          if (_itemNameController.text.trim().isEmpty || _selectedCatForItem == null) return;
                          final inbound = int.tryParse(_itemInboundController.text.trim()) ?? 0;
                          try {
                            final db = await DatabaseManager.instance.database;
                            await db.insert('items', {
                              'name': _itemNameController.text.trim(),
                              'category_id': _selectedCatForItem,
                              'total_inbound': inbound,
                            });
                            _itemNameController.clear();
                            _itemInboundController.text = '10';
                            await _loadData();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('الصنف موجود مسبقاً في هذه الفئة!')),
                            );
                          }
                        },
                        child: const Text('إضافة الصنف'),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120,
                  child: _items.isEmpty
                      ? const Center(child: Text('لا توجد أصناف مضافة'))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return ListTile(
                              dense: true,
                              title: Text(item['name'].toString()),
                              subtitle: Text('الفئة: ${item['cat_name']} | الوارد: ${item['total_inbound']}'),
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
                const Text('🏢 3. إدارة الجهات والأفراد (المستفيدين)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                        decoration: const InputDecoration(hintText: 'اسم الجهة أو الفرد (مثل الميمون)...'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                  child: const Text('إضافة المستفيد'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120,
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

// ================= 2. لوحة المؤشرات وجرد الذمة الشامل =================
class DashboardTab extends StatefulWidget {
  const DashboardTab({Key? key}) : super(key: key);

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  int totalInbound = 0;
  int totalCustody = 0;
  int totalLoss = 0;
  int totalRemaining = 0;

  List> entities = [];
  int? selectedEntityId;
  List> entityRecords = [];

  @override
  void initState() {
    super.initState();
    loadStatsAndEntities();
  }

  Future<void> loadStatsAndEntities() async {
    final db = await DatabaseManager.instance.database;
    
    final resIn = Sqflite.firstIntValue(await db.rawQuery('SELECT SUM(total_inbound) FROM items')) ?? 0;
    final resC = Sqflite.firstIntValue(await db.rawQuery('SELECT SUM(quantity) FROM custody_records')) ?? 0;
    final resL = Sqflite.firstIntValue(await db.rawQuery('SELECT SUM(quantity) FROM losses_records')) ?? 0;

    if (!mounted) return;
    setState(() {
      totalInbound = resIn;
      totalCustody = resC;
      totalLoss = resL;
      totalRemaining = resIn - (resC + resL);
    });

    final eList = await db.query('entities');
    if (!mounted) return;
    setState(() {
      entities = eList;
      if (entities.isNotEmpty && selectedEntityId == null) {
        selectedEntityId = entities.first['id'] as int;
      }
    });
  }

  Future<void> searchEntityRecords() async {
    if (selectedEntityId == null) return;
    final db = await DatabaseManager.instance.database;

    final custody = await db.rawQuery('''
      SELECT 'عهدة مصروفة' as type, cat.name as cat_name, i.name as item_name, c.quantity, c.status as info, c.issue_date as date
      FROM custody_records c
      JOIN categories cat ON c.category_id = cat.id
      JOIN items i ON c.item_id = i.id
      WHERE c.entity_id = ?
    ''', [selectedEntityId]);

    final losses = await db.rawQuery('''
      SELECT 'تالف / مفقود' as type, cat.name as cat_name, i.name as item_name, l.quantity, l.status || ' - ' || l.loss_reason as info, l.loss_date as date
      FROM losses_records l
      JOIN categories cat ON l.category_id = cat.id
      JOIN items i ON l.item_id = i.id
      WHERE l.entity_id = ?
    ''', [selectedEntityId]);

    if (!mounted) return;
    setState(() {
      entityRecords = [...custody, ...losses];
    });
    loadStatsAndEntities();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('📊 لوحة المؤشرات العامة وجرد ذمة الجهات (شامل جميع الفئات)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: StatCard(title: 'إجمالي الوارد', value: '$totalInbound', color: Colors.blueGrey)),
            Expanded(child: StatCard(title: 'المصروف الفعلي', value: '$totalCustody', color: Colors.blue)),
          ],
        ),
        Row(
          children: [
            Expanded(child: StatCard(title: 'التالف والمفقود', value: '$totalLoss', color: Colors.red)),
            Expanded(child: StatCard(title: 'المتبقي بالمخزن', value: '$totalRemaining', color: Colors.green)),
          ],
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: loadStatsAndEntities,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
          child: const Text('🔄 تحديث الإحصائيات العامة'),
        ),
        const Divider(height: 30),
        const Text('🔍 كشف الذمة الشامل لـ (جهة / فرد مثل الميمون)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          value: selectedEntityId,
          decoration: const InputDecoration(labelText: 'اختر الجهة / الفرد المستفيد'),
          items: entities.map((e) => DropdownMenuItem<int>(value: e['id'] as int, child: Text('${e['name']} (${e['type']})'))).toList(),
          onChanged: (val) => setState(() => selectedEntityId = val),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: searchEntityRecords,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          child: const Text('عرض الكشف الشامل (مصروف + تالف)'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 280,
          child: entityRecords.isEmpty
              ? const Center(child: Text('اختر جهة واضغط عرض لجلب السجلات'))
              : ListView.builder(
                  itemCount: entityRecords.length,
                  itemBuilder: (ctx, idx) {
                    final rec = entityRecords[idx];
                    final isLoss = rec['type'] == 'تالف / مفقود';
                    return Card(
                      color: isLoss ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                      child: ListTile(
                        title: Text('${rec['type']} - ${rec['item_name']} (${rec['cat_name']})', style: TextStyle(color: isLoss ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold)),
                        subtitle: Text('الكمية: ${rec['quantity']} | التفاصيل: ${rec['info']}\nالتاريخ: ${rec['date']}'),
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  const StatCard({Key? key, required this.title, required this.value, required this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 5),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ================= 3. شاشة الإعدادات =================
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

// ================= 4. سجلات العهد والإتلاف لكل فئة =================
class CategoryRecordsView extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  final String customColumns;
  const CategoryRecordsView({
    Key? key,
    required this.categoryId,
    required this.categoryName,
    required this.customColumns,
  }) : super(key: key);

  @override
  State<CategoryRecordsView> createState() => _CategoryRecordsViewState();
}

class _CategoryRecordsViewState extends State<CategoryRecordsView> {
  List> _records = [];
  List> _lossRecords = [];
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
    final List> records = (await db.rawQuery('''
      SELECT r.*, i.name as item_name, e.name as entity_name
      FROM custody_records r
      JOIN items i ON r.item_id = i.id
      JOIN entities e ON r.entity_id = e.id
      WHERE r.category_id = ?
      ORDER BY r.id DESC
    ''', [widget.categoryId]))
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final List> losses = (await db.rawQuery('''
      SELECT l.*, i.name as item_name, COALESCE(e.name, 'مخزن عام') as entity_name
      FROM losses_records l
      JOIN items i ON l.item_id = i.id
      LEFT JOIN entities e ON l.entity_id = e.id
      WHERE l.category_id = ?
      ORDER BY l.id DESC
    ''', [widget.categoryId]))
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final List> items = (await db.query(
      'items',
      where: 'category_id = ?',
      whereArgs: [widget.categoryId],
    ))
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final List> entities = (await db.query('entities'))
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    if (!mounted) return;

    setState(() {
      _records = records;
      _lossRecords = losses;
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
    String selectedStatus = 'تم التحقق والاستلام';
    final qtyController = TextEditingController(text: '1');
    final orderRefController = TextEditingController();
    final notesController = TextEditingController();

    // التعامل مع الأعمدة المخصصة للفئة إن وجدت
    final cols = widget.customColumns.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    final Map<String, TextEditingController> extraControllers = {};
    for (var col in cols) {
      extraControllers[col] = TextEditingController();
    }

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
                      ...cols.map((col) => TextField(
                            controller: extraControllers[col],
                            decoration: InputDecoration(labelText: col),
                          )),
                      DropdownButtonFormField<String>(
                        value: selectedStatus,
                        decoration: const InputDecoration(labelText: 'الحالة الميدانية'),
                        items: const [
                          DropdownMenuItem(value: 'معلقة (بانتظار التحقق)', child: Text('معلقة (بانتظار التحقق)')),
                          DropdownMenuItem(value: 'تم التحقق والاستلام', child: Text('تم التحقق والاستلام')),
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
                      final Map<String, String> extraData = {};
                      extraControllers.forEach((key, controller) {
                        extraData[key] = controller.text.trim();
                      });

                      final db = await DatabaseManager.instance.database;
                      await db.insert('custody_records', {
                        'category_id': widget.categoryId,
                        'entity_id': selectedEntityId,
                        'item_id': selectedItemId,
                        'quantity': qty,
                        'order_ref': orderRefController.text.trim(),
                        'status': selectedStatus,
                        'issue_date': DateTime.now().toString().split(' ')[0],
                        'extra_data': jsonEncode(extraData),
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
      extraControllers.forEach((_, c) => c.dispose());
    });
  }

  // نافذة تسجيل إتلاف من العهدة عند النقر المزدوج أو الضغط
  void _showLossDialog(Map<String, dynamic> record) {
    final maxQty = record['quantity'] as int;
    final qtyController = TextEditingController(text: '1');
    final reasonController = TextEditingController();
    final notesController = TextEditingController();
    String lossStatus = 'تالف كلي';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text('تسجيل إتلاف / مفقود (${record['item_name']})'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المستفيد: ${record['entity_name']}'),
                      Text('الكمية الحالية المتوفرة: $maxQty'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'الكمية المراد إتلافها أو خصمها'),
                      ),
                      DropdownButtonFormField<String>(
                        value: lossStatus,
                        decoration: const InputDecoration(labelText: 'حالة التلف'),
                        items: const [
                          DropdownMenuItem(value: 'تالف كلي', child: Text('تالف كلي')),
                          DropdownMenuItem(value: 'تالف جزئي', child: Text('تالف جزئي')),
                          DropdownMenuItem(value: 'مفقود', child: Text('مفقود')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => lossStatus = val);
                        },
                      ),
                      TextField(
                        controller: reasonController,
                        decoration: const InputDecoration(labelText: 'سبب الإتلاف'),
                      ),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(labelText: 'ملاحظات'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () async {
                      int lossQty = int.tryParse(qtyController.text.trim()) ?? 1;
                      if (lossQty > maxQty) lossQty = maxQty;
                      if (lossQty <= 0) return;

                      final db = await DatabaseManager.instance.database;
                      // 1. تسجيل في جدول الخسائر والإتلاف
                      await db.insert('losses_records', {
                        'category_id': widget.categoryId,
                        'custody_record_id': record['id'],
                        'item_id': record['item_id'],
                        'entity_id': record['entity_id'],
                        'quantity': lossQty,
                        'status': lossStatus,
                        'loss_reason': reasonController.text.trim(),
                        'loss_date': DateTime.now().toString().split(' ')[0],
                        'notes': notesController.text.trim(),
                      });

                      // 2. تحديث أو حذف سجل العهدة الأصلي
                      final remaining = maxQty - lossQty;
                      if (remaining > 0) {
                        await db.update(
                          'custody_records',
                          {'quantity': remaining},
                          where: 'id = ?',
                          whereArgs: [record['id']],
                        );
                      } else {
                        await db.delete(
                          'custody_records',
                          where: 'id = ?',
                          whereArgs: [record['id']],
                        );
                      }

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _loadCategoryData();
                    },
                    child: const Text('خصم وتسجيل الإتلاف'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF1E293B),
            child: const TabBar(
              tabs: [
                Tab(text: '📋 سجل العهد وحركات الصرف'),
                Tab(text: '⚠️ سجل الإتلاف والخسائر'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // تاب 1: العهد
                Scaffold(
                  body: _records.isEmpty
                      ? Center(child: Text('لا توجد عهد مسجلة في (${widget.categoryName})'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12.0),
                          itemCount: _records.length,
                          itemBuilder: (context, index) {
                            final rec = _records[index];
                            return Card(
                              child: ListTile(
                                title: Text('${rec['entity_name']} - ${rec['item_name']} (الكمية: ${rec['quantity']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  'الحالة: ${rec['status']} | التاريخ: ${rec['issue_date'] ?? '-'}\nالمرجع: ${rec['order_ref'] ?? '-'}\n💡 انقر مطولاً أو اضغط على أيقونة الإتلاف لتسجيل تلف/خصم',
                                ),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.warning, color: Colors.amber),
                                      tooltip: 'تسجيل إتلاف',
                                      onPressed: () => _showLossDialog(rec),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () async {
                                        final db = await DatabaseManager.instance.database;
                                        await db.delete('custody_records', where: 'id = ?', whereArgs: [rec['id']]);
                                        _loadCategoryData();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: _showAddRecordDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('صرف عهدة جديدة'),
                  ),
                ),
                // تاب 2: الإتلاف والخسائر
                Scaffold(
                  body: _lossRecords.isEmpty
                      ? const Center(child: Text('لا توجد سجلات إتلاف أو خسائر'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12.0),
                          itemCount: _lossRecords.length,
                          itemBuilder: (context, index) {
                            final loss = _lossRecords[index];
                            return Card(
                              color: Colors.red.withOpacity(0.15),
                              child: ListTile(
                                title: Text('${loss['entity_name']} - ${loss['item_name']} (تالف: ${loss['quantity']})', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                subtitle: Text('الحالة: ${loss['status']} | السبب: ${loss['loss_reason'] ?? '-'}\nالتاريخ: ${loss['loss_date'] ?? '-'}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () async {
                                    final db = await DatabaseManager.instance.database;
                                    await db.delete('losses_records', where: 'id = ?', whereArgs: [loss['id']]);
                                    _loadCategoryData();
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
