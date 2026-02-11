Future<bool> hasNetworkInterface() async {
  // Non-Flutter contexts (ex: dart run tooling) do not expose platform
  // connectivity APIs. Fallback to HTTP probe only.
  return true;
}
