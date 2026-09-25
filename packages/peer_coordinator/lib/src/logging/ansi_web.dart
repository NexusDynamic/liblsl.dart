/// Browser consoles render ANSI escape codes as literal garbage, so never
/// emit them. Use CSS-styled `console.log` if colour is ever wanted here.
bool get ansiSupported => false;
