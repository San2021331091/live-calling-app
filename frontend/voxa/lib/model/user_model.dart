class UserModel {
  final String id;
  final String name;
  final String phone;
  final String bio;
  final String avatarUrl;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.bio = '',
    this.avatarUrl = '',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      bio: json['bio'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
    );
  }
}
