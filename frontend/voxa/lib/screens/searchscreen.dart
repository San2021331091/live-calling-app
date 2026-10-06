import 'dart:async';

import 'package:flutter/material.dart';
import 'package:voxa/customui/gradient_app_bar_background.dart';
import 'package:voxa/model/user_model.dart';
import 'package:voxa/pages/individualpage.dart';
import 'package:voxa/services/api_client.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<UserModel> _users = [];
  bool _isSearching = false;
  bool _isLoading = true;
  String? _error;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
    _loadUsers();
  }

  void _onQueryChanged() {
    setState(() => _isSearching = _searchController.text.trim().isNotEmpty);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _loadUsers);
  }

  Future<void> _loadUsers() async {
    final query = _searchController.text.trim();
    final requestVersion = ++_requestVersion;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final users = await ApiClient.instance.loadUsers(query: query);
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _users = users;
        _isLoading = false;
        _isSearching = query.isNotEmpty;
      });
    } on ApiException catch (exception) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _error = exception.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _error = 'Could not load users. Check your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openChat(UserModel user) async {
    try {
      final chat = await ApiClient.instance.createDirectChat(userId: user.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IndividualPage(chatModel: chat)),
      );
    } on ApiException catch (exception) {
      if (mounted) _showError(exception.message);
    } catch (_) {
      if (mounted) _showError('Could not start this chat. Check your connection.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: const GradientAppBarBackground(),
        title: _buildSearchBar(),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: _buildResults(),
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: _loadUsers, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_users.isEmpty) {
      return Center(
        child: Text(
          _isSearching ? 'No users found' : 'No other users yet',
          style: const TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (_, index) => _buildUserCard(_users[index]),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        color: const Color(0xFFF0F4F1),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Color(0xFF75827B)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Color(0xFF26362E)),
              decoration: const InputDecoration(
                hintText: 'Search by name or phone...',
                hintStyle: TextStyle(color: Color(0xFF87928C)),
                border: InputBorder.none,
              ),
              keyboardType: TextInputType.text,
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () => _searchController.clear(),
              child: const Icon(Icons.close, color: Color(0xFF75827B)),
            ),
        ],
      ),
    );
  }

  Widget _buildUserCard(UserModel user) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE6F3ED),
          child: Text(
            user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF168A62),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(user.name),
        subtitle: Text(user.phone),
        trailing: const Icon(Icons.chat_bubble_outline_rounded),
        onTap: () => _openChat(user),
      ),
    );
  }
}
