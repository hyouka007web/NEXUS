enum BlockReason { adHost, redirectNoGesture }

/// Ein einzelnes Blockier-Ereignis fürs Bottom-Panel — Pendant zu Kotlins
/// `RedirectShield.BlockReason` + der zugehörigen Panel-Anzeige.
class BlockEvent {
  final String url;
  final BlockReason reason;

  const BlockEvent({required this.url, required this.reason});

  String get label => switch (reason) {
        BlockReason.adHost => 'Werbe-/Tracker-Domain blockiert',
        BlockReason.redirectNoGesture => 'Weiterleitung blockiert',
      };
}
