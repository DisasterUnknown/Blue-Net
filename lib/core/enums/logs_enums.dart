enum LogTypes {
  info,
  success,
  error;

  String get displayName {
    switch (this) {
      case LogTypes.info:
        return 'Info';
      case LogTypes.success:
        return 'Warning';
      case LogTypes.error:
        return 'Error';
    }
  }
}
