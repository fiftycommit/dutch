import 'dart:js_interop';

@JS('dutchTableCardMotion')
external JSObject? get _bridge;

bool get available => _bridge != null;

@JS('dutchTableCardMotion.updateHand')
external void _updateHand(JSObject element, JSString data);

@JS('dutchTableCardMotion.updateDrawn')
external void _updateDrawn(JSObject element, JSString data);

void updateHand(Object element, String data) =>
    _updateHand(element as JSObject, data.toJS);

void updateDrawn(Object element, String data) =>
    _updateDrawn(element as JSObject, data.toJS);
