import 'package:flutter_test/flutter_test.dart';

import 'package:mentorspace/models/profile.dart';

void main() {
  test('Profile.initials derives from the name', () {
    expect(
      const Profile(id: '1', role: 'mentor', fullName: 'Ada Lovelace').initials,
      'AL',
    );
    expect(
      const Profile(id: '2', role: 'client', fullName: 'Sam').initials,
      'SA',
    );
  });
}
