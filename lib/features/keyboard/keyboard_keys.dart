const int keyboardLeftCtrlModifier = 0x01;
const int keyboardLeftShiftModifier = 0x02;

const Map<String, int> plainKeyMap = {
  '1': 0x1e,
  '2': 0x1f,
  '3': 0x20,
  '4': 0x21,
  '5': 0x22,
  '6': 0x23,
  '7': 0x24,
  '8': 0x25,
  '9': 0x26,
  '0': 0x27,
  '\n': 0x28,
  '\b': 0x2a,
  '\t': 0x2b,
  ' ': 0x2c,
  '-': 0x2d,
  '=': 0x2e,
  '[': 0x2f,
  ']': 0x30,
  '\\': 0x31,
  ';': 0x33,
  "'": 0x34,
  '`': 0x35,
  ',': 0x36,
  '.': 0x37,
  '/': 0x38,
};

const Map<String, int> shiftedKeyMap = {
  '!': 0x1e,
  '@': 0x1f,
  '#': 0x20,
  r'$': 0x21,
  '%': 0x22,
  '^': 0x23,
  '&': 0x24,
  '*': 0x25,
  '(': 0x26,
  ')': 0x27,
  '_': 0x2d,
  '+': 0x2e,
  '{': 0x2f,
  '}': 0x30,
  '|': 0x31,
  ':': 0x33,
  '"': 0x34,
  '~': 0x35,
  '<': 0x36,
  '>': 0x37,
  '?': 0x38,
};

class KeyboardKeySpec {
  const KeyboardKeySpec({
    required this.label,
    required this.keyCode,
    this.modifiers = 0,
    this.flex = 1,
    this.isModifierAction = false,
  });

  final String label;
  final int keyCode;
  final int modifiers;
  final int flex;
  final bool isModifierAction;
}
