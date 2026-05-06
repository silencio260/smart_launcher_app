class ContactInfo {
  final String displayName;
  final String phoneNumber;
  final String? photoUri;

  const ContactInfo({
    required this.displayName,
    required this.phoneNumber,
    this.photoUri,
  });

  factory ContactInfo.fromMap(Map<dynamic, dynamic> map) {
    return ContactInfo(
      displayName: map['displayName'] as String,
      phoneNumber: map['phoneNumber'] as String,
      photoUri: map['photoUri'] as String?,
    );
  }
}
