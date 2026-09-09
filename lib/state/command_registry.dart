/// Stable command IDs. UI widgets should call commands through these IDs;
/// keybindings can therefore be remapped without changing the widgets.
class NexusCommands {
  NexusCommands._();
  static const palette='command.palette';
  static const focusAddress='browser.focusAddress';
  static const newTab='browser.newTab';
  static const closeTab='browser.closeTab';
  static const back='browser.back';
  static const forward='browser.forward';
  static const reload='browser.reload';
  static const harvest='browser.harvest';
  static const splitVertical='pane.splitVertical';
  static const splitHorizontal='pane.splitHorizontal';
  static const terminal='pane.terminal';
  static const devtools='pane.devtools';
  static const harvesterDebug='pane.harvesterDebug';
  static const browserPane='pane.browser';
  static const frameless='browser.frameless';
  static const workspaceSave='workspace.save';
  static const workspaceOpen='workspace.open';
  static const settingsTheme='settings.theme';
  static const settingsKeybindings='settings.keybindings';
  static const downloads='library.downloads';
  static const mediathek='library.mediathek';
}
