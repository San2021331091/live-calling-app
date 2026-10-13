import 'package:flutter/material.dart';
import 'package:voxa/screens/voxa_ai_screen.dart';

class VoxaAIAvatar extends StatelessWidget {
  const VoxaAIAvatar({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: Image.asset(
      'assets/VoxaAI.jpg',
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        color: const Color(0xFFDDF4F4),
        child: const Icon(Icons.auto_awesome, color: Color(0xFF087C8B)),
      ),
    ),
  );
}

class VoxaAITile extends StatelessWidget {
  const VoxaAITile({super.key});
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFEDF8F7),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: ListTile(
      leading: const VoxaAIAvatar(),
      title: const Text(
        'VoxaAI',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: const Text('Ask, learn, write, imagine'),
      trailing: const Icon(Icons.auto_awesome, color: Color(0xFF087C8B)),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const VoxaAIScreen())),
    ),
  );
}
