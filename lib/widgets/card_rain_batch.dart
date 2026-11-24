import 'dart:typed_data';

typedef CardRainTrack = ({
  String asset,
  double width,
  double height,
  double opacity,
});

typedef CardRainBatch = ({
  double duration,
  double sampleInterval,
  int frameCount,
  List<CardRainTrack> tracks,
  Float64List frames,
});

typedef NextCardRainBatch = CardRainBatch Function(double width, double height);
