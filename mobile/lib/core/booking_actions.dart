import '../data/models.dart';

/// Ce que le salon peut faire d'un rendez-vous dans son agenda (§3.3).
enum BookingAction {
  /// Le client est venu : encaisser.
  complete,

  /// Le client n'est pas venu.
  noShow,

  /// Annuler le rendez-vous — le client est prévenu.
  cancel,
}

/// Actions proposées pour un rendez-vous, à l'instant [now].
///
/// C'est par ces gestes que l'app sait si le client est venu : « خلّص » s'il
/// est venu, « ما جاش » sinon. Un client marqué absent par erreur reste
/// encaissable.
List<BookingAction> bookingActions(Booking booking, DateTime now) => [
      if (booking.status == BookingStatus.confirmed ||
          booking.status == BookingStatus.inProgress ||
          booking.status == BookingStatus.noShow)
        BookingAction.complete,
      // Avant l'heure, on ne peut pas savoir qu'il ne viendra pas.
      if (booking.status == BookingStatus.confirmed &&
          booking.start != null &&
          !booking.start!.isAfter(now))
        BookingAction.noShow,
      if (booking.status == BookingStatus.pending ||
          booking.status == BookingStatus.confirmed)
        BookingAction.cancel,
    ];
