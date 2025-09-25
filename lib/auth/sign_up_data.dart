class SignUpData {
  String firstName = '';
  String lastName  = '';
  // Phone entry
  String countryCode = '+1';  // default
  String phoneLocal  = '';    // user-typed (any formatting)
  String phone       = '';    // normalized "digits only" with country code prefix
}
