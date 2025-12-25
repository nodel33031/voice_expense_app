import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // 解決 Undefined name 'Firebase'
import 'package:firebase_auth/firebase_auth.dart'; // 解決 FirebaseAuth 相關問題
import 'package:cloud_firestore/cloud_firestore.dart'; // 解決 FirebaseFirestore 相關問題
// import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
void main() async {
  // 1. 確保 Flutter 引擎已初始化
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  // 初始化 Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ProAccountingApp());
}

// 修正：確保 StatelessWidget 有 build 方法
class ProAccountingApp extends StatelessWidget {
  const ProAccountingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '秒朗陪星', // 換一個可愛的日系名稱
      debugShowCheckedModeBanner: false,
      
      // --- 日系可愛主題設定 ---
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,

        textTheme:
            GoogleFonts.mPlusRounded1cTextTheme(
              ThemeData.light().textTheme,
            ).copyWith(
              bodyMedium: GoogleFonts.mPlusRounded1c(
                color: const Color(0xFF5F5F5F),
              ),
            ),

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD1DC),
          primary: const Color(0xFFFFB7B2),
          secondary: const Color(0xFFB2E2F2),
          // 解決警告：
          surface: const Color(0xFFFDFDFD),
        ),

        // 確保 Scaffold 的底色也是乾淨的米白色
        scaffoldBackgroundColor: const Color(0xFFFDFDFD),

        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          elevation: 20,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final String geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? "";
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  bool _isLoading = false;
  bool _showChart = false;
  bool _isMicBarExpanded = true;
  String _realTimeWords = "說「昨天早餐50元」或點擊左側鍵盤";
  List<Map<String, dynamic>> _history = [];
  DateTime _selectedDay = DateTime.now();
  String _selectedTab = "支出";
  String _timeRange = "月";

  // 登入狀態變數
  bool _hasLoggedIn = false;
  User? _currentUser;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // 請將下方的 ID 替換為你在 Firebase/Google Cloud Console 取得的 Web Client ID
    clientId:
        '861794811820-ochhte84mkuqq889qtku1a4ikmee4njq.apps.googleusercontent.com',
  );
  void _saveToLocal() {
    // 這裡放置你原本要儲存到本地 (如 SharedPreferences) 的邏輯
    // 如果暫時沒邏輯，可以先留空避免報錯
    print("資料已執行本地儲存程序");
  }

  @override
  void initState() {
    super.initState();
    // 監聽登入狀態切換
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
        if (user != null) {
          _loadDataFromCloud(); // 只有在有 user 時才執行
        }
      }
    });
    _loadHistory();
  }
  // --- 補齊缺失的方法 ---

  // 處理雲端同步邏輯 (目前先印出 Log)
  Future<void> _loadDataFromCloud() async {
    if (_currentUser == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('transactions')
          .get();

      // 修改 _loadDataFromCloud 中的映射邏輯
      setState(() {
        _history = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': data['id']?.toString() ?? doc.id,
            'item': data['item']?.toString() ?? '未命名項目',
            'amount': (data['amount'] ?? 0).toDouble(), // 確保是 double
            'category':
                data['category']?.toString() ?? '未分類', // 防範 null category
            'date': data['date']?.toString() ?? '2025-01-01', // 防範 null date
            'type': data['type']?.toString() ?? '支出',
          };
        }).toList();
      });
    } catch (e) {
      print("❌ 載入過程崩潰: $e");
    }
  }

  // Google 登入邏輯處理 (需搭配 google_sign_in 套件)
  Future<void> _handleGoogleSignIn() async {
    try {
      // 1. 啟動 Google 登入視窗
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      // 如果使用者取消登入，直接結束
      if (googleUser == null) return;

      // 2. 關鍵修正：在 if 外面取得驗證物件，確保下方的 credential 讀得到
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // 打印 Token (測試用)
      print("Access Token: ${googleAuth.accessToken}");

      // 3. 建立 Firebase 憑證
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. 登入 Firebase
      await FirebaseAuth.instance.signInWithCredential(credential);
      print("Web 登入成功！");
    } catch (e) {
      // 如果出現 "Couldn't find constructor" 錯誤，請執行下方提到的修復指令
      print("登入出錯: $e");
    }
  }

  // 登入彈窗按鈕組件
  Widget _buildLoginButton({
    required String label,
    required Color color,
    required IconData icon,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(25),
          border: color == Colors.white
              ? Border.all(color: Colors.grey.shade300)
              : null,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: textColor, size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 分類與配色 (包含收入項目) ---
  final Map<String, Color> _categoryColors = {
    "早餐": Color(0xFFFFE5B4),
    "午餐": Color(0xFFFFCCBB),
    "晚餐": Color(0xFFFFABAB),
    "交通": Color(0xFFC5E1A5),
    "薪資收入": Color(0xFFFFD54F),
    "利息收入": Color(0xFFFFF59D),
    "旅遊費": Color(0xFFB2EBF2),
    "娛樂費": Color(0xFFD1C4E9),
    "其他支出": Color(0xFFF5F5F5),
    "其他收入": Color(0xFFFFECB3),
  };

  void _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('history_stable_v6');
    if (data != null) {
      setState(() {
        _history = List<Map<String, dynamic>>.from(json.decode(data));
      });
    }
  }

  void _saveRecord(Map<String, dynamic> record) async {
    // 1. 生成唯一 ID 並同步寫入物件，確保刪除功能能對準 docId
    String docId = DateTime.now().millisecondsSinceEpoch.toString();
    record['id'] = docId;

    // 2. 確保日期存在。如果傳入的 record 沒帶 date，則預設為選中的那一天
    record['date'] ??= DateFormat('yyyy-MM-dd').format(_selectedDay);

    // 3. 補齊其餘欄位預設值，防止 UI 渲染 null 報錯
    record['item'] ??= "未命名項目";
    record['amount'] ??= 0.0;
    record['type'] ??= "支出";
    record['category'] ??= "未分類";

    setState(() {
      _history.insert(0, record);
      // 依日期排序，讓新加入的資料出現在正確的時間軸位置
      _history.sort((a, b) => b['date'].compareTo(a['date']));
    });

    _saveToLocal(); // 更新本地緩存

    if (_currentUser != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('transactions')
            .doc(docId)
            .set(record);
        print("✅ 資料已歸類至 ${record['date']} 並上傳雲端");
      } catch (e) {
        print("❌ 雲端儲存失敗: $e");
      }
    }
  }

  Future<void> _syncToFirestore(Map<String, dynamic> item) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // 未登入則略過雲端同步

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('transactions')
        .add({
          ...item,
          'timestamp': FieldValue.serverTimestamp(), // 紀錄精確存入時間
        });
  }

  // --- 關鍵保留：刪除功能 ---
  void _deleteRecord(String id) async {
    // 1. 先從本地記憶體狀態中移除，讓 UI 即時更新
    setState(() {
      _history.removeWhere((item) => item['id'] == id);
    });

    // 2. 更新本地持久化儲存 (SharedPreferences)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('history_stable_v6', json.encode(_history));

    // 3. 同步刪除雲端資料庫 (Firestore)
    if (_currentUser != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('transactions')
            .doc(id) // 確保這裡的 id 與 Firestore 中的文件 ID 一致
            .delete();
        print("雲端資料已成功刪除");
      } catch (e) {
        print("雲端刪除失敗: $e");
        // 選做：如果雲端刪除失敗，可以在這裡跳出提示或將資料加回 _history
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    try {
      if (_currentUser != null) {
        String uid = _currentUser!.uid;

        // 1. 刪除 Firestore 雲端資料
        var collection = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('transactions');
        var snapshots = await collection.get();
        for (var doc in snapshots.docs) {
          await doc.reference.delete();
        }
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();

        // 2. 刪除 Firebase Auth 帳號身分
        await _currentUser!.delete();
      }

      // 3. 清空本地狀態與快取 (與登出邏輯相同)
      setState(() {
        _currentUser = null;
        _history = [];
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('history_stable_v6');

      _resetState("帳號與資料已永久刪除");
    } catch (e) {
      print("刪除帳號失敗: $e");
      // 如果因為太久沒登入而失敗，Firebase 會要求重新驗證身分
      _resetState("為了安全，請重新登入後再執行刪除");
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          "⚠️ 刪除帳號",
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          "確定要刪除帳號嗎？此動作將永久抹除雲端與本地的所有帳務紀錄，且無法恢復。",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              _handleDeleteAccount(); // 執行刪除邏輯
            },
            child: const Text("確定刪除", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- 語音與 AI 解析 (帶有強效重設) ---
  void _toggleListening() async {
    if (_isLoading) return;
    if (!_isListening) {
      if (await _speech.initialize(onError: (e) => _resetState("語音初始化失敗"))) {
        setState(() {
          _isListening = true;
          _realTimeWords = "正在聽...";
        });
        _speech.listen(
          localeId: 'zh_TW',
          onResult: (result) {
            setState(() => _realTimeWords = result.recognizedWords);
            if (result.finalResult) {
              _stopAndProcess(result.recognizedWords);
            }
          },
        );
      }
    } else {
      _stopAndProcess("");
    }
  }

  void _stopAndProcess(String text) {
    _speech.stop();
    setState(() => _isListening = false);
    if (text.isNotEmpty) _processWithAI(text);
  }

  void _resetState(String msg) => setState(() {
    _isListening = false;
    _isLoading = false;
    _realTimeWords = msg;
  });

  Future<void> _processWithAI(String text) async {
    setState(() => _isLoading = true);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      final response = await http
          .post(
            // 請將路徑中的模型名稱改為 gemini-3-flash-preview
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$geminiApiKey',
            ),
            body: json.encode({
              "contents": [
                {
                  "parts": [
                    {
                      "text":
                          "智慧記帳助手。今天是 $today。解析輸入為 JSON。分類：${_categoryColors.keys.join('、')}。格式：{\"item\": \"品項\", \"amount\": 數字, \"category\": \"分類\", \"date\": \"yyyy-MM-dd\", \"type\": \"支出或收入\"}。輸入：'$text'",
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final res = json.decode(utf8.decode(response.bodyBytes));
        final clean = res['candidates'][0]['content']['parts'][0]['text']
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        final parsed = json.decode(clean);
        _saveRecord(parsed);
        _resetState("✅ 已存入：${parsed['item']}");
      } else {
        _resetState("❌ 伺服器忙碌 (${response.statusCode})");
      }
    } catch (e) {
      _resetState("❌ 解析錯誤，請再試一次");
    } finally {
      // 這裡最重要：確保無論成功或失敗，加載狀態都會解除
      setState(() => _isLoading = false);
    }
  }

  // --- 關鍵新增：手動鍵盤輸入介面 ---
  void _showKeyboardInput() {
    String item = "";
    String amount = "";
    String category = "午餐";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 24,
          right: 24,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "手動輸入項目",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.brown,
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              decoration: const InputDecoration(
                labelText: "品項名稱",
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => item = v,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: "金額",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => amount = v,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField(
              value: category,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _categoryColors.keys
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => category = v.toString(),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB7B2),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                if (item.isNotEmpty && amount.isNotEmpty) {
                  _saveRecord({
                    "item": item,
                    "amount": double.parse(amount),
                    "category": category,
                    "type": category.contains("收入") ? "收入" : "支出",
                    // 🔥 關鍵修正：將目前日曆選中的日期格式化後存入
                    "date": DateFormat('yyyy-MM-dd').format(_selectedDay),
                  });
                  Navigator.pop(context);
                  _resetState("✅ 手動記帳成功：$item");
                }
              },
              child: const Text(
                "確定儲存",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> doc) {
    final itemController = TextEditingController(
      text: doc['item']?.toString() ?? "",
    );
    final amountController = TextEditingController(
      text: doc['amount']?.toString() ?? "",
    );
    // 取得目前資料的舊類別
    String selectedCategory = doc['category']?.toString() ?? "未分類";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        // 使用 StatefulBuilder 讓對話框內可以 setState
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text("修改帳務資料", style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: itemController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "項目",
                    labelStyle: TextStyle(color: Colors.grey),
                  ),
                ),
                TextField(
                  controller: amountController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "金額",
                    labelStyle: TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 20),
                // --- 加入類別選擇選單 ---
                DropdownButton<String>(
                  value: _categoryColors.containsKey(selectedCategory)
                      ? selectedCategory
                      : "未分類",
                  isExpanded: true,
                  dropdownColor: const Color(0xFF2C2C2C),
                  style: const TextStyle(color: Colors.white),
                  items: _categoryColors.keys.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setDialogState(() {
                        // 這裡使用對話框專用的 state
                        selectedCategory = newValue;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("取消"),
            ),
            ElevatedButton(
              onPressed: () {
                _updateRecord(doc['id'].toString(), {
                  "item": itemController.text,
                  "amount": double.tryParse(amountController.text) ?? 0.0,
                  "category": selectedCategory, // 儲存選中的新類別
                  "type": selectedCategory.contains("收入")
                      ? "收入"
                      : "支出", // 根據類別自動判斷類型
                  "date": doc['date'],
                });
                Navigator.pop(context);
              },
              child: const Text("儲存修改"),
            ),
          ],
        ),
      ),
    );
  }

  void _updateRecord(String id, Map<String, dynamic> updatedData) async {
    // 1. 本地狀態更新
    setState(() {
      int index = _history.indexWhere((h) => h['id'].toString() == id);
      if (index != -1) {
        updatedData['id'] = id; // 🔥 務必保留 ID，否則下次會找不到
        _history[index] = updatedData;
      }
    });

    // 2. 雲端更新
    if (_currentUser != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('transactions')
          .doc(id) // 指定要修改的文件 ID
          .update(updatedData); // 僅更新異動欄位
    }
  }

  // --- 確保保留：左滑刪除清單項 ---
  Widget _buildDismissibleItem(Map<String, dynamic> item) {
    // 安全提取欄位，提供預設值防止 null 崩潰
    final String id =
        item['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final String itemName = item['item']?.toString() ?? "未命名項目";
    final String category = item['category']?.toString() ?? "未分類";
    final String type = item['type']?.toString() ?? "支出";
    final double amount = (item['amount'] ?? 0.0).toDouble();

    // 安全取得顏色：如果類別不在定義中，給予灰色預設值
    Color categoryColor = _categoryColors[category] ?? Colors.grey;

    return Dismissible(
      key: Key(id), // 確保 Key 不為 null
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade50,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 25),
        child: const Icon(Icons.delete_forever, color: Colors.redAccent),
      ),
      onDismissed: (direction) =>
          _deleteRecord(item['id'].toString()), // 這裡必須有值
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5),
          ],
          border: Border.all(color: categoryColor.withValues(alpha: 0.4)),
        ),
        child: ListTile(
          onTap: () => _showEditDialog(item), // 點擊後彈出修改視窗
          leading: CircleAvatar(backgroundColor: categoryColor, radius: 10),
          title: Text(
            itemName, // 確保為 String
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            category, // 確保為 String
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(
            "${type == '收入' ? '+' : '-'}\$${amount.toStringAsFixed(0)}",
            style: TextStyle(
              color: type == '收入' ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  // --- 關鍵保留：可摺疊面板 + 新增鍵盤入口 ---
  Widget _buildVoiceKeyboardPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      height: _isMicBarExpanded ? 190 : 70,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 15,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _isMicBarExpanded = !_isMicBarExpanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              child: Icon(
                _isMicBarExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up,
                color: Colors.grey.shade400,
              ),
            ),
          ),
          if (_isMicBarExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                _realTimeWords,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 鍵盤輸入按鈕 (左側)
                IconButton(
                  icon: const Icon(
                    Icons.keyboard_outlined,
                    color: Colors.grey,
                    size: 32,
                  ),
                  onPressed: _showKeyboardInput,
                ),
                const SizedBox(width: 40),
                // 語音按鈕 (中間)
                GestureDetector(
                  onTap: _toggleListening,
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: _isListening
                        ? Colors.redAccent.shade100
                        : const Color(0xFFFFB7B2),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Icon(Icons.mic, color: Colors.white, size: 35),
                  ),
                ),
                const SizedBox(width: 72), // 視覺平衡用
              ],
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  // --- 2. 帳務報表區塊 (日系可愛風修正版) ---
Widget _buildChartSection() {
  DateTime now = DateTime.now();

  // 1. 資料過濾邏輯 (保持不變)
  List<Map<String, dynamic>> filteredList = _history.where((h) {
    if (h['date'] == null || h['type'] == null || h['category'] == null || h['amount'] == null)
      return false;
    try {
      DateTime hDate = DateFormat('yyyy-MM-dd').parse(h['date'].toString());
      if (_timeRange == "月") {
        return hDate.year == _selectedDay.year && hDate.month == _selectedDay.month;
      } else if (_timeRange == "近 6 個月") {
        return hDate.isAfter(now.subtract(const Duration(days: 180)));
      } else {
        return hDate.year == _selectedDay.year;
      }
    } catch (e) {
      return false;
    }
  }).toList();

  // 2. 統計計算
  Map<String, double> categoryStats = {};
  double totalAmount = 0;

  if (_selectedTab != "結餘") {
    for (var item in filteredList.where((h) => h['type'] == _selectedTab)) {
      String cat = (item['category'] ?? "未分類").toString();
      double amt = (item['amount'] ?? 0.0).toDouble();
      categoryStats[cat] = (categoryStats[cat] ?? 0) + amt;
      totalAmount += amt;
    }
  }

  return Container(
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(25), // 圓潤大卡片
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFFFD1DC)..withValues(alpha: 0.2), // 淺粉色呼吸感陰影
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: ExpansionTile(
      initiallyExpanded: true,
      // 移除預設的邊框線
      shape: const RoundedRectangleBorder(side: BorderSide.none),
      collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
      title: Row(
        children: [
          const Icon(Icons.analytics_rounded, color: Color(0xFFFFB7B2), size: 20),
          const SizedBox(width: 8),
          Text(
            "帳務報表",
            style: GoogleFonts.mPlusRounded1c(
              color: const Color(0xFF5F5F5F), // 柔和深灰文字
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            children: [
              // 第一層切換：支出/收入/結餘
              _buildSegmentedControl(
                ["支出", "收入", "結餘"],
                _selectedTab,
                (v) => setState(() => _selectedTab = v),
              ),
              const SizedBox(height: 8),
              // 第二層切換：時間區間
              _buildSegmentedControl(
                ["月", "近 6 個月", "年"],
                _timeRange,
                (v) => setState(() => _timeRange = v),
                isSecondary: true,
              ),
              const SizedBox(height: 25), // 增加留白

              // 3. 顯示內容
              if (_selectedTab != "結餘") ...[
                categoryStats.isNotEmpty
                    ? Column(
                        children: [
                          _buildDonutChart(
                            totalAmount,
                            categoryStats,
                          ),
                          const SizedBox(height: 25),
                          _buildCategoryList(totalAmount, categoryStats),
                        ],
                      )
                    : SizedBox(
                        height: 150,
                        child: Center(
                          child: Text(
                            "此期間尚無紀錄~",
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        ),
                      ),
              ] else ...[
                Builder(
                  builder: (context) {
                    double inc = 0;
                    double exp = 0;
                    for (var h in filteredList) {
                      double amt = (h['amount'] ?? 0).toDouble();
                      if (h['type'] == '收入') inc += amt;
                      else exp += amt;
                    }
                    return _buildBalanceSummary(income: inc, expense: exp);
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

  // --- 3. 核心輔助組件 (甜甜圈、清單、結餘) ---
  Widget _buildDonutChart(double total, Map<String, double> stats) {
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              centerSpaceRadius: 65,
              sectionsSpace: 4,
              sections: stats.entries
                  .map(
                    (e) => PieChartSectionData(
                      color: _categoryColors[e.key] ?? Colors.blueGrey,
                      value: e.value,
                      title: '',
                      radius: 25,
                      borderSide:  BorderSide(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "總$_selectedTab",
                // 💡 移除 const，因為 GoogleFonts 是方法調用
                style: GoogleFonts.mPlusRounded1c(
                  color: const Color(0xFFA0A0A0), // 柔和灰
                  fontSize: 14,
                  letterSpacing: 1.2, // 增加字距更具設計感
                ),
              ),
              // 💡 增加垂直間距，避免文字擠在一起
              const SizedBox(height: 6),
              Text(
                "\$${total.toInt()}",
                style: GoogleFonts.mPlusRounded1c(
                  fontSize: 26, // 數字放大，視覺更平衡
                  fontWeight: FontWeight.w800, // 極粗體展現可愛感
                  color: const Color(0xFF5F5F5F), // 深質感灰
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCategoryList(double total, Map<String, double> stats) {
    return Wrap(
      spacing: 20,
      runSpacing: 15,
      children: stats.entries.map((e) {
        double perc = total > 0 ? (e.value / total) * 100 : 0;
        return SizedBox(
          width: MediaQuery.of(context).size.width / 2 - 65,
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _categoryColors[e.key],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.key,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                "${perc.toStringAsFixed(1)}%",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // 修改：傳入過濾後的總收入與總支出
  Widget _buildBalanceSummary({
    required double income,
    required double expense,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _balanceDetail("收入", income, Colors.green),
          const Text("-", style: TextStyle(fontSize: 20, color: Colors.grey)),
          _balanceDetail("支出", expense, Colors.redAccent),
          const Text("=", style: TextStyle(fontSize: 20, color: Colors.grey)),
          _balanceDetail("結餘", income - expense, Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _balanceDetail(String label, double val, Color col) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(
          "\$${val.toInt()}",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: col,
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceItem(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Text(
          "\$${value.toInt()}",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // 通用的切換按鈕組件
  // --- 2. 通用切換按鈕組件 (對應 UI 調整) ---
  Widget _buildSegmentedControl(
    List<String> opts,
    String current,
    Function(String) onSelect, {
    bool isSecondary = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      height: isSecondary ? 32 : 42,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2D2D2D), width: 1),
      ),
      child: Row(
        children: opts.map((o) {
          bool sel = current == o;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(o),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? const Color.fromARGB(255, 255, 232, 157) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  o,
                  style: TextStyle(
                    fontSize: isSecondary ? 11 : 13,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    color: sel ? Colors.black : Colors.grey[600],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 結餘視圖組件
  Widget _buildBalanceView(double income, double expense) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _balanceItem("總收入", income, Colors.green),
          const Icon(Icons.remove, color: Colors.grey),
          _balanceItem("總支出", expense, Colors.red),
          const Icon(Icons.drag_handle, color: Colors.grey),
          _balanceItem("結餘", income - expense, Colors.blue),
        ],
      ),
    );
  }

  Widget _balanceItem(String label, double val, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 5),
        Text(
          "\$${val.toInt()}",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // 1. 生成符合設計圖風格的區塊數據
  List<PieChartSectionData> _getSections() {
    Map<String, double> data = {};
    for (var h in _history) {
      if (h['type'] == '支出') {
        data[h['category']] = (data[h['category']] ?? 0) + h['amount'];
      }
    }

    if (data.isEmpty) return [];

    return data.entries.map((e) {
      return PieChartSectionData(
        color: _categoryColors[e.key] ?? Colors.grey,
        value: e.value,
        title: '', // 不在圖上顯示文字
        radius: 50, // 甜甜圈的厚度
        // 關鍵設計：加上深色外框線
        borderSide: const BorderSide(color: Color(0xFF2D2D2D), width: 1.5),
      );
    }).toList();
  }

  // --- 1. 修正後的登出邏輯 (放在 _HomePageState 內) ---
  Future<void> _handleSignOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      await _googleSignIn.signOut();

      setState(() {
        _currentUser = null;
        _history = []; // 🔥 關鍵：清空記憶體，畫面才會變空白
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('history_stable_v6'); // 🔥 關鍵：清空本地暫存

      _resetState("已成功登出並清除本地資料");
    } catch (error) {
      print("登出失敗: $error");
    }
  }

  // --- 1. 帳戶設定與登入邏輯 ---
  // --- 2. 帳戶設定 UI ---
  void _showLoginSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          bool isLoggedIn = _currentUser != null;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "帳戶設定",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (!isLoggedIn) ...[
                  _buildLoginButton(
                    label: "使用 Google 登入",
                    color: Colors.white,
                    icon: Icons.g_mobiledata,
                    textColor: Colors.black,
                    onTap: () async {
                      await _handleGoogleSignIn();
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "登入後即可同步雲端帳本",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ] else ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(
                        _currentUser?.photoURL ?? "",
                      ),
                    ),
                    title: Text(
                      _currentUser?.displayName ?? "使用者",
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      _currentUser?.email ?? "",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildLoginButton(
                    label: "登出帳號",
                    color: Colors.white.withOpacity(0.1),
                    icon: Icons.logout,
                    textColor: Colors.white,
                    onTap: () async {
                      await _handleSignOut(); // 🔥 呼叫剛才寫好的完整登出邏輯
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 12),
                  // --- 補上刪除帳號功能 (iOS 審核必備) ---
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showDeleteConfirmation(); // 之前提供給你的確認對話框
                    },
                    child: const Text(
                      "刪除帳號與所有資料",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendarSection() {
    return TableCalendar(
      firstDay: DateTime.utc(2024),
      lastDay: DateTime.utc(2030),
      focusedDay: _selectedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          // 這裡將選中的日期存入 _selectedDay，後續 _saveRecord 就會抓到這個日期
        });
      },
      calendarFormat: CalendarFormat.month,
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
      ),
    );
  }

  Widget _buildAuthTag() {
    // 檢查是否登入 (使用你代碼中的 _currentUser)
    bool isLoggedIn = _currentUser != null;

    return GestureDetector(
      onTap: _showLoginSheet,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
        decoration: BoxDecoration(
          // 已登入用金色，未登入用深灰色
          color: isLoggedIn ? const Color(0xFFFFD54F) : const Color(0xFF2D2D2D),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            bottomLeft: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(-2, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isLoggedIn && _currentUser?.photoURL != null
                ? CircleAvatar(
                    radius: 10,
                    backgroundImage: NetworkImage(_currentUser!.photoURL!),
                  )
                : Icon(
                    isLoggedIn
                        ? Icons.cloud_done
                        : Icons.account_circle_outlined,
                    color: isLoggedIn ? Colors.black87 : Colors.white,
                    size: 18,
                  ),
            const SizedBox(width: 8),
            Text(
              isLoggedIn ? "已同步" : "未登入",
              style: TextStyle(
                color: isLoggedIn ? Colors.black87 : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
Widget build(BuildContext context) {
  final dailyList = _history
      .where(
        (i) => i['date'] == DateFormat('yyyy-MM-dd').format(_selectedDay),
      )
      .toList();

  return Scaffold(
    // 使用主題設定的日系底色
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    body: Column(
      children: [
        // A. 頂部標題與標籤 (簡潔、圓潤樣式)
        Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 10,
            bottom: 15,
            left: 20,
            right: 20,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 左側裝飾：可以用一個可愛小圖示或預留空間
              const Icon(Icons.auto_awesome, color: Color(0xFFFFD1DC), size: 24),
              const Text(
                "秒朗陪星", // 您目標圖片的標題
                style: TextStyle(
                  fontSize: 22, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  color: Color(0xFF5F5F5F),
                ),
              ),
              _buildAuthTag(), // 右側同步標籤
            ],
          ),
        ),

        // B. 可捲動內容
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    // 圖表區 (建議內部也改為馬卡龍配色)
                    _buildChartSection(), 
                    // 日曆區 (建議背景改為透明或淡淡粉色)
                    _buildCalendarSection(),
                  ],
                ),
              ),
              
              // 今日紀錄標題
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(left: 25, top: 20, bottom: 10),
                  child: Row(
                    children: [
                      Icon(Icons.bookmark_added, size: 18, color: Color(0xFFFFB7B2)),
                      SizedBox(width: 8),
                      Text(
                        "今日帳目",
                        style: TextStyle(
                          color: Color(0xFF9E9E9E), 
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 紀錄清單
              dailyList.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.pets, size: 48, color: const Color(0xFFFFD1DC).withOpacity(0.5)),
                            const SizedBox(height: 10),
                            const Text(
                              "今天還沒記帳喔汪！",
                              style: TextStyle(color: Colors.grey, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SliverPadding(
                      // 增加底部邊距，確保不會被底部的黃色語音鈕擋住
                      padding: const EdgeInsets.only(bottom: 150, left: 10, right: 10),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildDismissibleItem(dailyList[index]),
                          childCount: dailyList.length,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    ),
    // 底部語音鍵盤 (建議修改按鈕為圓形、黃色系)
    bottomSheet: _buildVoiceKeyboardPanel(),
  );
}
}
