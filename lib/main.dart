import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const PhoneToPCApp());
}

class PhoneToPCApp extends StatelessWidget {
  const PhoneToPCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phone to PC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E78FF)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ── 连接状态 ──────────────────────────────────────
enum ConnState { disconnected, connecting, connected }

// ── 主页 ──────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  WebSocketChannel? _channel;
  ConnState _connState = ConnState.disconnected;
  String _statusMsg = '未连接';
  String _lastSent = '';
  bool _sendOnEnter = false; // 是否回车发送

  // 发送模式：type=自动输入, clipboard=剪贴板
  String _sendMode = 'type';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('last_ip') ?? '';
      _sendMode = prefs.getString('send_mode') ?? 'type';
      _sendOnEnter = prefs.getBool('send_on_enter') ?? false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ip', _ipController.text.trim());
    await prefs.setString('send_mode', _sendMode);
    await prefs.setBool('send_on_enter', _sendOnEnter);
  }

  // ── 连接/断开 ──────────────────────────────────
  void _toggleConnection() {
    if (_connState == ConnState.connected) {
      _disconnect();
    } else {
      _connect();
    }
  }

  void _connect() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      _showSnack('请输入电脑 IP 地址');
      return;
    }

    setState(() {
      _connState = ConnState.connecting;
      _statusMsg = '连接中...';
    });

    final uri = Uri.parse('ws://$ip:8765');
    try {
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen(
        (message) {
          // 收到服务端确认
          try {
            final data = jsonDecode(message);
            if (data['status'] == 'ok') {
              setState(() => _statusMsg = '✓ 已发送：$_lastSent');
            }
          } catch (_) {}
        },
        onDone: () {
          setState(() {
            _connState = ConnState.disconnected;
            _statusMsg = '连接已断开';
          });
        },
        onError: (e) {
          setState(() {
            _connState = ConnState.disconnected;
            _statusMsg = '连接错误：$e';
          });
        },
      );

      // WebSocket 连接是异步的，简单延迟后认为成功
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _connState == ConnState.connecting) {
          setState(() {
            _connState = ConnState.connected;
            _statusMsg = '已连接到 $ip';
          });
          _savePrefs();
          _textFocus.requestFocus();
        }
      });
    } catch (e) {
      setState(() {
        _connState = ConnState.disconnected;
        _statusMsg = '无法连接：$e';
      });
    }
  }

  void _disconnect() {
    _channel?.sink.close();
    _channel = null;
    setState(() {
      _connState = ConnState.disconnected;
      _statusMsg = '已断开';
    });
  }

  // ── 发送文字 ──────────────────────────────────
  void _sendText() {
    if (_connState != ConnState.connected) {
      _showSnack('请先连接电脑');
      return;
    }
    final text = _textController.text;
    if (text.isEmpty) return;

    final payload = jsonEncode({'text': text, 'mode': _sendMode});
    _channel!.sink.add(payload);
    _lastSent = text.length > 20 ? '${text.substring(0, 20)}...' : text;

    setState(() {
      _statusMsg = '发送中...';
      _textController.clear();
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ── UI ────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isConnected = _connState == ConnState.connected;
    final isConnecting = _connState == ConnState.connecting;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E78FF),
        foregroundColor: Colors.white,
        title: const Text('Phone to PC', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 连接卡片 ──────────────────
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('电脑 IP 地址',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF555555))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ipController,
                            enabled: !isConnected && !isConnecting,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              hintText: '例：192.168.1.100',
                              prefixIcon: const Icon(Icons.computer, color: Color(0xFF1E78FF)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            onSubmitted: (_) => _connect(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 90,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: isConnecting ? null : _toggleConnection,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isConnected ? Colors.red : const Color(0xFF1E78FF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: isConnecting
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(isConnected ? '断开' : '连接'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 状态指示
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected
                                ? Colors.green
                                : isConnecting
                                    ? Colors.orange
                                    : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_statusMsg,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: isConnected ? Colors.green.shade700 : Colors.grey.shade600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── 输入卡片 ──────────────────
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('输入文字',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF555555))),
                        // 发送模式切换
                        _buildModeChip(),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _textController,
                      focusNode: _textFocus,
                      enabled: isConnected,
                      maxLines: 5,
                      minLines: 3,
                      textInputAction: _sendOnEnter ? TextInputAction.send : TextInputAction.newline,
                      onSubmitted: _sendOnEnter ? (_) => _sendText() : null,
                      decoration: InputDecoration(
                        hintText: isConnected ? '在这里输入要发到电脑的文字...' : '请先连接电脑',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: isConnected ? _sendText : null,
                        icon: const Icon(Icons.send),
                        label: const Text('发 送', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E78FF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          disabledBackgroundColor: Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── 使用说明 ──────────────────
              _buildCard(
                color: const Color(0xFFF0F5FF),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('使用说明', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E78FF))),
                    SizedBox(height: 8),
                    Text('① 在电脑上运行 PhoneToPC.exe\n'
                        '② 鼠标悬停托盘图标查看 IP 地址\n'
                        '③ 在上方输入框填入 IP，点击连接\n'
                        '④ 输入文字，点发送即可自动输入到电脑光标处',
                        style: TextStyle(fontSize: 13, height: 1.7, color: Color(0xFF444444))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child, Color? color}) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildModeChip() {
    return Row(
      children: [
        const Text('模式：', style: TextStyle(fontSize: 12, color: Colors.grey)),
        GestureDetector(
          onTap: () {
            setState(() {
              _sendMode = _sendMode == 'type' ? 'clipboard' : 'type';
            });
            _savePrefs();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E78FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF1E78FF).withOpacity(0.3)),
            ),
            child: Text(
              _sendMode == 'type' ? '⌨️ 自动输入' : '📋 剪贴板',
              style: const TextStyle(fontSize: 12, color: Color(0xFF1E78FF), fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('回车键直接发送'),
                subtitle: const Text('开启后按回车发送，否则换行'),
                value: _sendOnEnter,
                onChanged: (v) {
                  setModalState(() => _sendOnEnter = v);
                  setState(() => _sendOnEnter = v);
                  _savePrefs();
                },
              ),
              ListTile(
                title: const Text('发送模式'),
                subtitle: Text(_sendMode == 'type' ? '自动输入到当前文本框' : '写入剪贴板（手动粘贴）'),
                trailing: Switch(
                  value: _sendMode == 'clipboard',
                  onChanged: (v) {
                    final mode = v ? 'clipboard' : 'type';
                    setModalState(() => _sendMode = mode);
                    setState(() => _sendMode = mode);
                    _savePrefs();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disconnect();
    _ipController.dispose();
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }
}
