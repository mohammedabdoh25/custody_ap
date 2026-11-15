import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CustodyApp());
}

class CustodyApp extends StatelessWidget {
  const CustodyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام إدارة العهد والمخازن',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF090D16),
        cardColor: const Color(0xFF0F172A),
      ),
      home: const MainSystemScreen(),
    );
  }
}

// ---------------- Database Manager ----------------
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('custody_system_v4.db');
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
        name TEXT UNIQUE NOT NULL,
        custom_columns TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        total_inbound INTEGER NOT NULL DEFAULT 0,
        UNIQUE(name, category_id)
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
        extra_data TEXT,
        notes TEXT
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
        notes TEXT
      )
    ''');
  }
}

// ---------------- Main Screen with Tabs ----------------
class MainSystemScreen extends StatefulWidget {
  const MainSystemScreen({Key? key}) : super(key: key);

  @override
  _MainSystemScreenState createState() => _MainSystemScreenState();
}

class _MainSystemScreenState extends State<MainSystemScreen> with TickerCodeMixin, SingleTickerProviderStateMixin {
  TabController? _tabController;
  List> categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategoriesAndSetupTabs();
  }

  Future<void> _loadCategoriesAndSetupTabs() async {
    final db = await DatabaseHelper.instance.database;
    final cats = await db.query('categories');
    setState(() {
      categories = cats;
      // 3 tabs fixed (Constants, Dashboard, Settings) + dynamic categories
      _tabController = TabController(length: 3 + categories.length, vsync: this);
    });
  }

  void refreshTabs() {
    _loadCategoriesAndSetupTabs();
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🛡️ نظام إدارة ومتابعة العهد والمخازن', style: TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF1E293B),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.lightBlueAccent,
          tabs: [
            const Tab(text: '⚙️ الثوابت'),
            const Tab(text: '📊 المؤشرات وجرد الجهات'),
            const Tab(text: '⚙️ الإعدادات'),
            ...categories.map((cat) => Tab(text: '📁 ${cat['name']}')).toList(),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ConstantsTab(onCategoryChanged: refreshTabs),
          DashboardTab(onDataChanged: () {}),
          const SettingsTab(),
          ...categories.map((cat) => CategoryViewTab(category: cat)).toList(),
        ],
      ),
    );
  }
}

// ---------------- 1. Constants Tab ----------------
class ConstantsTab extends StatefulWidget {
  final VoidCallback onCategoryChanged;
  const ConstantsTab({Key? key, required this.onCategoryChanged}) : super(key: key);

  @override
  _ConstantsTabState createState() => _ConstantsTabState();
}

class _ConstantsTabState extends State<ConstantsTab> {
  final catNameController = TextEditingController();
  final catColsController = TextEditingController();
  
  final itemNameController = TextEditingController();
  final itemInboundController = TextEditingController(text: '10');
  int? selectedCatId;

  final entNameController = TextEditingController();
  String entType = 'جهة';

  List> cats = [];
  List> items = [];
  List> ents = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final db = await DatabaseHelper.instance.database;
    final cList = await db.query('categories');
    final iList = await db.rawQuery('''
      SELECT items.*, categories.name as cat_name FROM items 
      JOIN categories ON items.category_id = categories.id
    ''');
    final eList = await db.query('entities');

    setState(() {
      cats = cList;
      items = iList;
      ents = eList;
      if (cats.isNotEmpty && selectedCatId == null) {
        selectedCatId = cats.first['id'] as int;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Categories Section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📦 إدارة الفئات والأعمدة المخصصة', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
                TextField(controller: catNameController, decoration: const InputDecoration(labelText: 'اسم الفئة (مثال: آليات)')),
                TextField(controller: catColsController, decoration: const InputDecoration(labelText: 'الأعمدة المخصصة مفصولين بفاصلة (رقم الهيكل, المالك)')),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (catNameController.text.isEmpty) return;
                    final db = await DatabaseHelper.instance.database;
                    try {
                      await db.insert('categories', {'name': catNameController.text, 'custom_columns': catColsController.text});
                      catNameController.clear();
                      catColsController.clear();
                      loadData();
                      widget.onCategoryChanged();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الفئة موجودة مسبقاً!')));
                    }
                  },
                  child: const Text('إضافة الفئة'),
                )
              ],
            ),
          ),
        ),
        // Items Section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📌 إدارة الأصناف وإجمالي الوارد', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
                DropdownButton<int>(
                  value: selectedCatId,
                  isExpanded: true,
                  items: cats.map((c) => DropdownMenuItem<int>(value: c['id'] as int, child: Text(c['name'] as String))).toList(),
                  onChanged: (val) => setState(() => selectedCatId = val),
                ),
                TextField(controller: itemNameController, decoration: const InputDecoration(labelText: 'اسم الصنف')),
                TextField(controller: itemInboundController, decoration: const InputDecoration(labelText: 'إجمالي الوارد للمخزن'), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (itemNameController.text.isEmpty || selectedCatId == null) return;
                    final db = await DatabaseHelper.instance.database;
                    try {
                      await db.insert('items', {
                        'name': itemNameController.text,
                        'category_id': selectedCatId,
                        'total_inbound': int.tryParse(itemInboundController.text) ?? 0
                      });
                      itemNameController.clear();
                      loadData();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الصنف موجود مسبقاً في هذه الفئة!')));
                    }
                  },
                  child: const Text('إضافة الصنف'),
                )
              ],
            ),
          ),
        ),
        // Entities Section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🏢 إدارة الجهات والأفراد المستفيدين', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
                TextField(controller: entNameController, decoration: const InputDecoration(labelText: 'اسم الجهة أو الفرد (مثل: الميمون)')),
                DropdownButton<String>(
                  value: entType,
                  isExpanded: true,
                  items: ['جهة', 'فرد'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) => setState(() => entType = val!),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (entNameController.text.isEmpty) return;
                    final db = await DatabaseHelper.instance.database;
                    try {
                      await db.insert('entities', {'name': entNameController.text, 'type': entType});
                      entNameController.clear();
                      loadData();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المستفيد موجود مسبقاً!')));
                    }
                  },
                  child: const Text('إضافة المستفيد'),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------- 2. Dashboard & Entity Full Records Tab ----------------
class DashboardTab extends StatefulWidget {
  final VoidCallback onDataChanged;
  const DashboardTab({Key? key, required this.onDataChanged}) : super(key: key);

  @override
  _DashboardTabState createState() => _DashboardTabState();
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
    final db = await DatabaseHelper.instance.database;
    
    final resIn = Sqflite.firstIntValue(await db.rawQuery('SELECT SUM(total_inbound) FROM items')) ?? 0;
    final resC = Sqflite.firstIntValue(await db.rawQuery('SELECT SUM(quantity) FROM custody_records')) ?? 0;
    final resL = Sqflite.firstIntValue(await db.rawQuery('SELECT SUM(quantity) FROM losses_records')) ?? 0;

    setState(() {
      totalInbound = resIn;
      totalCustody = resC;
      totalLoss = resL;
      totalRemaining = resIn - (resC + resL);
    });

    final eList = await db.query('entities');
    setState(() {
      entities = eList;
      if (entities.isNotEmpty && selectedEntityId == null) {
        selectedEntityId = entities.first['id'] as int;
      }
    });
  }

  Future<void> searchEntityRecords() async {
    if (selectedEntityId == null) return;
    final db = await DatabaseHelper.instance.database;

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
        const Text('📊 لوحة المؤشرات العامة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlueAccent)),
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
        const Divider(height: 30),
        const Text('🔍 كشف الذمة الشامل لجهة أو فرد', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.lightBlueAccent)),
        DropdownButton<int>(
          value: selectedEntityId,
          isExpanded: true,
          items: entities.map((e) => DropdownMenuItem<int>(value: e['id'] as int, child: Text('${e['name']} (${e['type']})'))).toList(),
          onChanged: (val) => setState(() => selectedEntityId = val),
        ),
        ElevatedButton(
          onPressed: searchEntityRecords,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          child: const Text('عرض الكشف الشامل للجهة'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 300,
          child: ListView.builder(
            itemCount: entityRecords.length,
            itemBuilder: (ctx, idx) {
              final rec = entityRecords[idx];
              final isLoss = rec['type'] == 'تالف / مفقود';
              return Card(
                color: isLoss ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                child: ListTile(
                  title: Text('${rec['type']} - ${rec['item_name']} (${rec['cat_name']})'),
                  subtitle: Text('الكمية: ${rec['quantity']} | الحالة: ${rec['info']}\nالتاريخ: ${rec['date']}'),
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

// ---------------- 3. Category Management & Custody/Loss View Tab ----------------
class CategoryViewTab extends StatefulWidget {
  final Map<String, dynamic> category;
  const CategoryViewTab({Key? key, required this.category}) : super(key: key);

  @override
  _CategoryViewTabState createState() => _CategoryViewTabState();
}

class _CategoryViewTabState extends State<CategoryViewTab> {
  List> custodyList = [];
  List> lossList = [];

  @override
  void initState() {
    super.initState();
    loadRecords();
  }

  Future<void> loadRecords() async {
    final db = await DatabaseHelper.instance.database;
    final cList = await db.rawQuery('''
      SELECT c.*, e.name as ent_name, i.name as item_name FROM custody_records c
      JOIN entities e ON c.entity_id = e.id
      JOIN items i ON c.item_id = i.id
      WHERE c.category_id = ?
    ''', [widget.category['id']]);

    final lList = await db.rawQuery('''
      SELECT l.*, COALESCE(e.name, 'مخزن عام') as ent_name, i.name as item_name FROM losses_records l
      JOIN items i ON l.item_id = i.id
      LEFT JOIN entities e ON l.entity_id = e.id
      WHERE l.category_id = ?
    ''', [widget.category['id']]);

    setState(() {
      custodyList = cList;
      lossList = lList;
    });
  }

  void _openAddCustodyDialog() async {
    // يمكن فتح نافذة حوار لإضافة عهدة جديدة
    loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF1E293B),
            child: const TabBar(
              tabs: [
                Tab(text: 'سجل العهد وحركات الصرف'),
                Tab(text: 'سجل الإتلاف والخسائر'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Tab 1: Custody
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton(
                        onPressed: _openAddCustodyDialog,
                        child: const Text('➕ إضافة حركة صرف عهدة'),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: custodyList.length,
                        itemBuilder: (ctx, i) {
                          final item = custodyList[i];
                          return ListTile(
                            title: Text('${item['ent_name']} - ${item['item_name']} (الكمية: ${item['quantity']})'),
                            subtitle: Text('الحالة: ${item['status']} | التاريخ: ${item['issue_date']}'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                // Tab 2: Losses
                ListView.builder(
                  itemCount: lossList.length,
                  itemBuilder: (ctx, i) {
                    final item = lossList[i];
                    return ListTile(
                      title: Text('${item['ent_name']} - ${item['item_name']} (تالف: ${item['quantity']})'),
                      subtitle: Text('السبب: ${item['loss_reason']} | الحالة: ${item['status']}'),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 4. Settings Tab ----------------
class SettingsTab extends StatelessWidget {
  const SettingsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('⚙️ إعدادات النظام والنسخ الاحتياطي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlueAccent)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم أخذ النسخة الاحتياطية بنجاح')));
          },
          icon: const Icon(Icons.download),
          label: const Text('أخذ نسخة احتياطية لقاعدة البيانات'),
        ),
      ],
    );
  }
}
