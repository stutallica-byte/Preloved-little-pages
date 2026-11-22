export const basketChangeEvent = 'preloved-basket-change';

const storageKey = 'preloved-little-pages-basket';

export function normalizeBookId(value: unknown): string | undefined {
  if (typeof value === 'string' && /^\d+$/.test(value.trim())) return value.trim();
  if (typeof value === 'number' && Number.isSafeInteger(value) && value >= 0) return String(value);
  return undefined;
}

export function getBasketIds(): string[] {
  const stored = window.localStorage.getItem(storageKey);
  if (!stored) return [];

  let parsed: unknown;
  try {
    parsed = JSON.parse(stored);
  } catch (error) {
    console.error('The saved basket data could not be read:', error);
    return [];
  }

  if (!Array.isArray(parsed)) {
    console.error('The saved basket data is not a list of book IDs.');
    return [];
  }

  return [...new Set(parsed.map(normalizeBookId).filter((id): id is string => id !== undefined))];
}

function saveBasketIds(ids: string[]): void {
  window.localStorage.setItem(storageKey, JSON.stringify([...new Set(ids)]));
  window.dispatchEvent(new Event(basketChangeEvent));
}

export function addBasketId(id: string): boolean {
  const ids = getBasketIds();
  if (ids.includes(id)) return false;
  saveBasketIds([...ids, id]);
  return true;
}

export function removeBasketId(id: string): boolean {
  const ids = getBasketIds();
  const updatedIds = ids.filter((savedId) => savedId !== id);
  if (updatedIds.length === ids.length) return false;
  saveBasketIds(updatedIds);
  return true;
}

export function onBasketChange(callback: () => void): () => void {
  const listener = () => callback();
  window.addEventListener(basketChangeEvent, listener);
  window.addEventListener('storage', listener);
  return () => {
    window.removeEventListener(basketChangeEvent, listener);
    window.removeEventListener('storage', listener);
  };
}
