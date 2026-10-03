/// What a ready-session `checkPrinterStatus` poll should do with the native payload.
///
/// Bluetooth `isConnected` stays true after the printer powers off until the
/// socket is closed, so the poll result is the backup signal when no
/// disconnect event arrives.
enum StatusPollDecision {
  /// Payload is status JSON. A null battery is still a live link (AC power).
  applyStatus,

  /// The printer is gone, or the poll itself failed while the session was ready.
  linkLost,

  /// Not a status payload and not a known dead-link token.
  ignore,
}

/// Classifies one `checkPrinterStatus` result while the session is ready.
///
/// [rawText] is the method-channel string. `"Not Connected"` and `"Not TCP"`
/// are not JSON and must not be parsed. [timedOut] and [channelFailed] mean
/// the poll could not reach the printer (hung SGD or a plugin error).
///
/// A JSON object with a missing battery stays [StatusPollDecision.applyStatus].
/// AC-powered printers and a flaky SGD scalar are not a disconnect.
StatusPollDecision interpretStatusPoll({
  String? rawText,
  bool timedOut = false,
  bool channelFailed = false,
}) {
  if (timedOut || channelFailed) return StatusPollDecision.linkLost;
  final text = rawText?.trim() ?? '';
  if (text == 'Not Connected' || text == 'Not TCP') {
    return StatusPollDecision.linkLost;
  }
  if (text.startsWith('{')) return StatusPollDecision.applyStatus;
  return StatusPollDecision.ignore;
}
