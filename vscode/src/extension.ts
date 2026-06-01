import * as vscode from 'vscode';
import { execFile } from 'child_process';
import * as http from 'http';

function getBinary(): string {
  return vscode.workspace.getConfiguration('sensei').get('binaryPath', 'sensei');
}

interface SenseiResult {
  stdout: string;
  stderr: string;
}

function runSensei(args: string[]): Promise<SenseiResult> {
  return new Promise((resolve, reject) => {
    execFile(getBinary(), args, { timeout: 60000 }, (err, stdout, stderr) => {
      if (err) { reject(stderr || err.message); return; }
      resolve({ stdout, stderr });
    });
  });
}

function stripAnsi(text: string): string {
  return text.replace(/\x1b\[[0-9;]*m/g, '');
}

function extractTipText(raw: string): string {
  return stripAnsi(raw)
    .split('\n')
    .filter(l => l.trim() && !l.startsWith('╭') && !l.startsWith('╰') && !l.startsWith('│  💡'))
    .map(l => l.replace(/│/g, '').trim())
    .filter(Boolean)
    .join(' ');
}

function checkOllama(): Promise<boolean> {
  return new Promise(resolve => {
    const req = http.get('http://localhost:11434', { timeout: 2000 }, () => resolve(true));
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
  });
}

function panelHtml(content: string): string {
  return `<!DOCTYPE html>
<html>
<head>
<style>
  body { font-family: monospace; padding: 16px; background: var(--vscode-editor-background); color: var(--vscode-editor-foreground); }
  pre { white-space: pre-wrap; font-size: 14px; line-height: 1.6; }
  .thinking { opacity: 0.5; font-style: italic; }
</style>
</head>
<body><pre>${content}</pre></body>
</html>`;
}

function openPanel(title: string): vscode.WebviewPanel {
  const panel = vscode.window.createWebviewPanel('senseiPanel', title, vscode.ViewColumn.Beside, {});
  panel.webview.html = panelHtml('<span class="thinking">Thinking...</span>');
  return panel;
}

function showPanel(_context: vscode.ExtensionContext, title: string, content: string, panel?: vscode.WebviewPanel) {
  const p = panel ?? vscode.window.createWebviewPanel('senseiPanel', title, vscode.ViewColumn.Beside, {});
  p.webview.html = panelHtml(extractTipText(content));
}

let statusBarItem: vscode.StatusBarItem;
let ollamaInterval: NodeJS.Timeout;

async function updateOllamaStatus() {
  const online = await checkOllama();
  if (online) {
    statusBarItem.text = '$(check) Ollama';
    statusBarItem.color = new vscode.ThemeColor('charts.green');
    statusBarItem.tooltip = 'Ollama is running';
  } else {
    statusBarItem.text = '$(x) Ollama';
    statusBarItem.color = new vscode.ThemeColor('editorWarning.foreground');
    statusBarItem.tooltip = 'Ollama not reachable';
  }
}

export function activate(context: vscode.ExtensionContext) {
  statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  statusBarItem.show();
  updateOllamaStatus();
  ollamaInterval = setInterval(updateOllamaStatus, 30000);
  context.subscriptions.push(statusBarItem);

  context.subscriptions.push(
    vscode.commands.registerCommand('sensei.tip', async () => {
      try {
        const { stdout } = await runSensei(['tip']);
        vscode.window.showInformationMessage(extractTipText(stdout));
      } catch (e) {
        vscode.window.showErrorMessage(`Sensei: ${e}`);
      }
    }),

    vscode.commands.registerCommand('sensei.explain', async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;
      const selection = editor.document.getText(editor.selection);
      const text = selection || editor.document.lineAt(editor.selection.active.line).text;
      const lang = editor.document.languageId;
      const lineCount = editor.document.lineCount;
      const selStart = editor.selection.start.line;
      const selEnd = editor.selection.end.line;
      const ctxStart = Math.max(0, selStart - 30);
      const ctxEnd = Math.min(lineCount - 1, selEnd + 30);
      const fileContext = editor.document.getText(
        new vscode.Range(ctxStart, 0, ctxEnd, editor.document.lineAt(ctxEnd).text.length)
      );
      const panel = openPanel('Sensei: Explain');
      try {
        const { stdout } = await runSensei(['explain', text, '--lang', lang, '--context', fileContext]);
        // Offline fallback notice is now rendered inside the tip box on stdout.
        showPanel(context, 'Sensei: Explain', stdout, panel);
      } catch (e) {
        panel.dispose();
        vscode.window.showErrorMessage(`Sensei: ${e}`);
      }
    }),

    vscode.commands.registerCommand('sensei.ask', async () => {
      const question = await vscode.window.showInputBox({ prompt: 'Sensei >' });
      if (!question) return;
      const panel = openPanel('Sensei: Answer');
      try {
        const { stdout } = await runSensei(['ask', question]);
        // Offline fallback notice is now rendered inside the tip box on stdout.
        showPanel(context, 'Sensei: Answer', stdout, panel);
      } catch (e) {
        panel.dispose();
        vscode.window.showErrorMessage(`Sensei: ${e}`);
      }
    })
  );

  // ambient tip on startup
  runSensei(['tip']).then(({ stdout }) => {
    vscode.window.showInformationMessage('💡 ' + extractTipText(stdout));
  }).catch(() => {});
}

export function deactivate() {
  clearInterval(ollamaInterval);
}
