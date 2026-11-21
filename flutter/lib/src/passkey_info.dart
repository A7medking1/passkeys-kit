/// One of the user's passkeys, as the server lists it. The key itself stays
/// on the phone; the server never sends its public key either.
class PasskeyInfo {
  /// Creates a passkey description.
  const PasskeyInfo({
    required this.id,
    required this.name,
    this.deviceType = 'singleDevice',
    this.backedUp = false,
    this.createdAt,
    this.lastUsedAt,
  });

  /// Reads one item of `GET /` (or the answer of `register/verify`).
  factory PasskeyInfo.fromJson(Map<String, dynamic> json) => PasskeyInfo(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    deviceType: json['deviceType'] as String? ?? 'singleDevice',
    backedUp: json['backedUp'] as bool? ?? false,
    createdAt: _date(json['createdAt']),
    lastUsedAt: _date(json['lastUsedAt']),
  );

  /// The credential id, to delete it.
  final String id;

  /// What the user sees, like the phone's model.
  final String name;

  /// `singleDevice`, or `multiDevice` for a synced passkey.
  final String deviceType;

  /// Whether the password manager backed it up (iCloud Keychain, Google).
  final bool backedUp;

  /// When it was added.
  final DateTime? createdAt;

  /// When it last signed the user in. Null until it does.
  final DateTime? lastUsedAt;

  /// It syncs to the user's other devices.
  bool get isSynced => deviceType == 'multiDevice';

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  @override
  bool operator ==(Object other) =>
      other is PasskeyInfo &&
      other.id == id &&
      other.name == name &&
      other.deviceType == deviceType &&
      other.backedUp == backedUp &&
      other.createdAt == createdAt &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode =>
      Object.hash(id, name, deviceType, backedUp, createdAt, lastUsedAt);
}
