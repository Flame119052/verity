import fs from 'fs';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import { Session, Message } from '../types.js';
import { safeReadFileSync } from '../utils/safeFs.js';

export class SessionStore {
  private vaultPath: string;
  private sessionsDir: string;

  constructor(vaultPath: string) {
    this.vaultPath = vaultPath;
    this.sessionsDir = path.join(vaultPath, 'Progress', 'Sessions');
    this.ensureDir();
  }

  private ensureDir(): void {
    if (!fs.existsSync(this.sessionsDir)) {
      fs.mkdirSync(this.sessionsDir, { recursive: true });
    }
  }

  // Session IDs are always server-generated UUIDs (see create() below), but
  // they arrive back from routes as req.params.id — unvalidated user input.
  // Reject anything that isn't a plain identifier before using it as a path
  // component, so a crafted id like "../../etc" can never escape sessionsDir.
  private assertSafeId(id: string): void {
    if (!/^[a-zA-Z0-9-]+$/.test(id)) {
      throw new Error(`Invalid session id: ${id}`);
    }
  }

  private getSessionPath(id: string): string {
    this.assertSafeId(id);
    return path.join(this.sessionsDir, `${id}.json`);
  }

  private getAttachmentsDir(id: string): string {
    this.assertSafeId(id);
    return path.join(this.sessionsDir, id, 'attachments');
  }

  create(
    mode: 'ask' | 'research',
    provider: 'claude' | 'codex' | 'antigravity',
    model: string,
    effort: string,
    courseName?: string
  ): Session {
    const id = uuidv4();
    const now = new Date().toISOString();

    const session: Session = {
      id,
      provider,
      mode,
      model,
      effort,
      courseName,
      claudeSessionId: undefined,
      codexSessionId: undefined,
      createdAt: now,
      updatedAt: now,
      messages: []
    };

    const sessionPath = this.getSessionPath(id);
    fs.writeFileSync(sessionPath, JSON.stringify(session, null, 2));

    return session;
  }

  get(id: string): Session | null {
    try {
      const sessionPath = this.getSessionPath(id);
      if (!fs.existsSync(sessionPath)) {
        return null;
      }
      const content = safeReadFileSync(sessionPath);
      return JSON.parse(content) as Session;
    } catch {
      return null;
    }
  }

  list(): Array<{
    id: string;
    provider: 'claude' | 'codex' | 'antigravity';
    mode: 'ask' | 'research';
    model: string;
    courseName?: string;
    createdAt: string;
    updatedAt: string;
    lastMessagePreview?: string;
  }> {
    this.ensureDir();

    if (!fs.existsSync(this.sessionsDir)) {
      return [];
    }

    const files = fs.readdirSync(this.sessionsDir);
    const summaries: Array<{
      id: string;
      provider: 'claude' | 'codex' | 'antigravity';
      mode: 'ask' | 'research';
      model: string;
      courseName?: string;
      createdAt: string;
      updatedAt: string;
      lastMessagePreview?: string;
    }> = [];

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const id = file.slice(0, -5); // Remove .json extension
      const session = this.get(id);
      if (!session) continue;

      let lastMessagePreview: string | undefined;
      if (session.messages.length > 0) {
        const lastMsg = session.messages[session.messages.length - 1];
        lastMessagePreview = lastMsg.text.substring(0, 80);
      }

      summaries.push({
        id: session.id,
        provider: session.provider,
        mode: session.mode,
        model: session.model,
        courseName: session.courseName,
        createdAt: session.createdAt,
        updatedAt: session.updatedAt,
        lastMessagePreview
      });
    }

    // Sort by updatedAt descending
    summaries.sort(
      (a, b) =>
        new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
    );

    return summaries;
  }

  appendMessage(id: string, message: Message): Session {
    const session = this.get(id);
    if (!session) {
      throw new Error(`Session not found: ${id}`);
    }

    session.messages.push(message);
    session.updatedAt = new Date().toISOString();

    const sessionPath = this.getSessionPath(id);
    fs.writeFileSync(sessionPath, JSON.stringify(session, null, 2));

    return session;
  }

  setClaudeSessionId(id: string, claudeSessionId: string): void {
    const session = this.get(id);
    if (!session) {
      throw new Error(`Session not found: ${id}`);
    }

    session.claudeSessionId = claudeSessionId;
    session.updatedAt = new Date().toISOString();

    const sessionPath = this.getSessionPath(id);
    fs.writeFileSync(sessionPath, JSON.stringify(session, null, 2));
  }

  setCodexSessionId(id: string, codexSessionId: string): void {
    const session = this.get(id);
    if (!session) {
      throw new Error(`Session not found: ${id}`);
    }

    session.codexSessionId = codexSessionId;
    session.updatedAt = new Date().toISOString();

    const sessionPath = this.getSessionPath(id);
    fs.writeFileSync(sessionPath, JSON.stringify(session, null, 2));
  }


  delete(id: string): void {
    const sessionPath = this.getSessionPath(id);
    if (fs.existsSync(sessionPath)) {
      fs.unlinkSync(sessionPath);
    }

    // Also delete the session's folder (which contains attachments if any)
    const sessionFolder = path.join(this.sessionsDir, id);
    if (fs.existsSync(sessionFolder)) {
      fs.rmSync(sessionFolder, { recursive: true, force: true });
    }
  }
}
