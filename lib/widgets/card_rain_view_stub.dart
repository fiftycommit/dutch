import 'package:flutter/widgets.dart';

import 'card_rain_batch.dart';

const webCardRainAvailable = false;

Widget buildWebCardRain({
  required bool active,
  required NextCardRainBatch nextBatch,
}) =>
    throw UnsupportedError('Browser card rain is web only');
