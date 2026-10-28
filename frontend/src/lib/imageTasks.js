// Session-only task state. Credentials, attachments and media bytes stay out.
export const IMAGE_TASK_LIMIT = 3;
export function createImageTaskStore(limit = IMAGE_TASK_LIMIT, identity = "guest") {
  let tasks = [];
  const listeners = new Set();
  const recovery = new Map();
  const publish = () => { for (const listener of listeners) listener(); };
  return {
    identity,
    getSnapshot: () => tasks,
    subscribe(listener) { listeners.add(listener); return () => listeners.delete(listener); },
    registerRecovery(id, query) { recovery.set(id, query); },
    recover(id) { return recovery.get(id)?.(); },
    start(id, { prompt, model, billingMode }) {
      if (tasks.some(task => task.id === id) || tasks.filter(task => task.active).length >= limit) return false;
      tasks = [{ id, prompt, model, billingMode, status: "running", active: true, createdAt: Date.now(), images: [] }, ...tasks];
      tasks = tasks.filter((task, index) => task.active || index < 30);
      for (const id of recovery.keys()) if (!tasks.some(task => task.id === id)) recovery.delete(id);
      publish(); return true;
    },
    finish(id, { images = [], error = null, pending = false, prompt } = {}) {
      const task = tasks.find(item => item.id === id);
      if (!task || (!task.active && task.status !== "pending")) return;
      tasks = tasks.map(item => item.id !== id ? item : { ...item, active: false,
        status: error ? (pending ? "pending" : "failed") : "completed",
        images, error, prompt: prompt ?? item.prompt });
      publish();
    },
  };
}

export function referenceCapability(spec) {
  const limit = spec?.maxReferences ?? spec?.references ?? 8;
  return { limit, disabled: limit === 0 };
}
