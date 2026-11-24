import 'dart:js_interop';

@JS('dutchCardReveal')
external JSObject? get _bridge;

bool get webRevealAvailable => _bridge != null;

@JS('dutchCardReveal.prepare')
external void _prepare(JSString asset);

@JS('dutchCardReveal.show')
external JSPromise<JSAny?> _show(JSArray<JSString> assets, JSString back);

@JS('dutchCardReveal.cancel')
external void cancelWebReveal();

void prepareWebReveal(String asset) => _prepare(asset.toJS);

Future<void> showWebReveal(List<String> assets, String back) async {
  await _show(assets.map((asset) => asset.toJS).toList().toJS, back.toJS).toDart;
}
